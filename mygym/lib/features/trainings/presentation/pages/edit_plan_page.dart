import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/plans_controller.dart';

class EditPlanPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final bool isAi;
  const EditPlanPage({super.key, required this.plan, this.isAi = false});

  @override
  State<EditPlanPage> createState() => _EditPlanPageState();
}

class _EditPlanPageState extends State<EditPlanPage> {
  late final PlansController _controller;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _totalWorkoutsCtrl;
  late final TextEditingController _totalExercisesCtrl;
  late final TextEditingController _trainingMinutesCtrl;
  late final TextEditingController _userLevelCtrl;
  late DateTime _start;
  late DateTime _end;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _categoryLocked = true;

  @override
  void initState() {
    super.initState();
    print('🔍 EditPlanPage initState called');
    print('🔍 Plan ID: ${widget.plan['id']}');
    
    try {
      _controller = Get.find<PlansController>();
      print('🔍 PlansController found successfully');
    } catch (e) {
      print('❌ Error finding PlansController: $e');
      rethrow;
    }
    
    print('🔍 Edit Plan - Initial plan data:');
    print('Plan keys: ${widget.plan.keys}');
    // total_exercises not edited anymore
    print('total_workouts: ${widget.plan['total_workouts']}');
    // training_minutes no longer displayed in header; preserved in data
    
    _categoryCtrl = TextEditingController(text: widget.plan['exercise_plan_category']?.toString() ?? widget.plan['exercise_plan']?.toString() ?? '');
    _nameCtrl = TextEditingController(text: widget.plan['name']?.toString() ?? widget.plan['exercise_plan']?.toString() ?? '');
    _totalWorkoutsCtrl = TextEditingController(text: widget.plan['total_workouts']?.toString() ?? '');
    
    _totalExercisesCtrl = TextEditingController(text: '');
    
    _trainingMinutesCtrl = TextEditingController(text: widget.plan['training_minutes']?.toString() ?? widget.plan['total_training_minutes']?.toString() ?? '');
    _userLevelCtrl = TextEditingController(text: widget.plan['user_level']?.toString() ?? '');
    _start = DateTime.tryParse(widget.plan['start_date']?.toString() ?? '') ?? DateTime.now();
    _end = DateTime.tryParse(widget.plan['end_date']?.toString() ?? '') ?? DateTime.now();
    
    print('🔍 Edit Plan - Initial controller values:');
    print('_totalExercisesCtrl.text: ${_totalExercisesCtrl.text}');
    print('_totalWorkoutsCtrl.text: ${_totalWorkoutsCtrl.text}');
    print('_userLevelCtrl.text: ${_userLevelCtrl.text}');
    
    // Always load full plan data to ensure all fields are populated
    // This ensures total_exercises and other fields are properly loaded
    _loadFullPlan();
  }

  Future<void> _loadFullPlan() async {
    final id = int.tryParse(widget.plan['id']?.toString() ?? '');
    print('🔍 _loadFullPlan called with ID: $id');
    print('🔍 Plan data: ${widget.plan}');
    print('🔍 isAi flag: ${widget.isAi}');
    
    if (id == null) {
      print('❌ Invalid plan ID, cannot load full plan');
      return;
    }
    setState(() => _loading = true);
    try {
      print('🔍 Calling get full plan for ${widget.isAi ? 'AI' : 'manual'} with ID $id');
      
      Map<String, dynamic> full;
      
      // Check if this is an assignment (has assignment_id)
      if (widget.plan['assignment_id'] != null) {
        print('🔍 Plan has assignment_id, fetching assignment details');
        final assignmentId = widget.plan['assignment_id'];
        full = await _controller.getAssignmentDetails(assignmentId);
      } else if (widget.isAi) {
        print('🔍 Fetching AI generated plan');
        try {
          full = await _controller.getAiGeneratedPlan(id);
        } catch (e) {
          print('❌ Failed to fetch AI plan: $e');
          // If AI plan fails, use the plan data we already have
          full = Map<String, dynamic>.from(widget.plan);
        }
      } else {
        print('🔍 Fetching manual plan');
        try {
          full = await _controller.getManualPlan(id);
        } catch (e) {
          print('❌ Failed to fetch manual plan: $e');
          try {
            // Try AI plan as fallback
            full = await _controller.getAiGeneratedPlan(id);
          } catch (aiError) {
            print('❌ AI plan fallback also failed: $aiError');
            // If both fail, use the plan data we already have
            full = Map<String, dynamic>.from(widget.plan);
          }
        }
      }
      
      print('🔍 Plan fetch completed successfully');
      
      print('🔍 Edit Plan - Full plan data received:');
      print('Full plan keys: ${full.keys}');
      // total_exercises present but not editable
      print('total_workouts: ${full['total_workouts']}');
      // debug: training_minutes present in backend
      
      // Update all fields from the full plan data
      _categoryCtrl.text = (full['exercise_plan_category'] ?? full['exercise_plan'])?.toString() ?? '';
      _nameCtrl.text = full['name']?.toString() ?? full['exercise_plan']?.toString() ?? '';
      _totalWorkoutsCtrl.text = full['total_workouts']?.toString() ?? '';
      
      _totalExercisesCtrl.text = '';
      
      _trainingMinutesCtrl.text = (full['training_minutes'] ?? full['total_training_minutes'])?.toString() ?? '';
      // Prefer plan-level user_level, else derive from first item
      String derivedUserLevel = '';
      if ((full['user_level']?.toString().isNotEmpty ?? false)) {
        derivedUserLevel = full['user_level'].toString();
      } else if (full['items'] is List && (full['items'] as List).isNotEmpty) {
        final Map first = Map<String, dynamic>.from((full['items'] as List).first as Map);
        derivedUserLevel = first['user_level']?.toString() ?? '';
      }
      _userLevelCtrl.text = derivedUserLevel;
      
      print('🔍 Edit Plan - Controllers updated:');
      print('_totalExercisesCtrl.text: ${_totalExercisesCtrl.text}');
      print('_totalWorkoutsCtrl.text: ${_totalWorkoutsCtrl.text}');
      print('_userLevelCtrl.text: ${_userLevelCtrl.text}');
      
      // Update dates
      if (full['start_date'] != null) {
        _start = DateTime.tryParse(full['start_date']?.toString() ?? '') ?? DateTime.now();
      }
      if (full['end_date'] != null) {
        _end = DateTime.tryParse(full['end_date']?.toString() ?? '') ?? DateTime.now();
      }
      
      // Update items
      if (full['items'] is List) {
        _items = (full['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      setState(() {});
    } catch (e) {
      print('❌ Error in _loadFullPlan: $e');
      print('❌ Error type: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load plan details. The plan may not exist or you may not have permission to edit it.'),
            backgroundColor: Colors.red,
          ),
        );
        // Navigate back if we can't load the plan
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _nameCtrl.dispose();
    _totalWorkoutsCtrl.dispose();
    _totalExercisesCtrl.dispose();
    _trainingMinutesCtrl.dispose();
    _userLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = int.tryParse(widget.plan['id']?.toString() ?? '');
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing plan id')));
      return;
    }
    final totalMinutes = _items.fold<int>(0, (sum, it) => sum + (int.tryParse(it['minutes']?.toString() ?? it['training_minutes']?.toString() ?? '0') ?? 0));
    final payload = widget.isAi
        ? {
            'exercise_plan': _categoryCtrl.text.trim(),
            'name': _nameCtrl.text.trim(),
            'total_workouts': _items.length,
            'total_training_minutes': totalMinutes,
            'user_level': _userLevelCtrl.text.trim(),
            'start_date': _start.toIso8601String().split('T').first,
            'end_date': _end.toIso8601String().split('T').first,
            'items': _items.map((e) => {
                  'name': e['workout_name']?.toString() ?? e['name']?.toString() ?? '',
                  'exercise_types': e['exercise_types']?.toString() ?? '',
                  'sets': int.tryParse(e['sets']?.toString() ?? '') ?? 0,
                  'reps': int.tryParse(e['reps']?.toString() ?? '') ?? 0,
                  'weight': double.tryParse(e['weight']?.toString() ?? e['weight_kg']?.toString() ?? '') ?? 0,
                  'training_minutes': int.tryParse(e['training_minutes']?.toString() ?? e['minutes']?.toString() ?? '') ?? 0,
                  'user_level': _userLevelCtrl.text.trim(),
                }).toList(),
          }
        : {
            'exercise_plan_category': _categoryCtrl.text.trim(),
            'name': _nameCtrl.text.trim(),
            'total_workouts': _items.length,
            'training_minutes': totalMinutes,
            'user_level': _userLevelCtrl.text.trim(),
            'start_date': _start.toIso8601String().split('T').first,
            'end_date': _end.toIso8601String().split('T').first,
            'items': _items.map((e) => {
                  'workout_name': e['workout_name']?.toString() ?? '',
                  'exercise_types': e['exercise_types']?.toString() ?? '',
                  'sets': int.tryParse(e['sets']?.toString() ?? '') ?? 0,
                  'reps': int.tryParse(e['reps']?.toString() ?? '') ?? 0,
                  'weight_kg': double.tryParse(e['weight_kg']?.toString() ?? '') ?? 0,
                  'minutes': int.tryParse(e['minutes']?.toString() ?? '') ?? 0,
                  'user_level': _userLevelCtrl.text.trim(),
                  'exercise_plan_category': _categoryCtrl.text.trim(),
                }).toList(),
          };
    
    print('🔍 Edit Plan - Save payload:');
    print('Payload: $payload');
    print('total_exercises value: ${payload['total_exercises']}');
    print('total_exercises controller text: ${_totalExercisesCtrl.text}');
    try {
      if (widget.isAi) {
        await _controller.updateAiGeneratedPlan(id, payload);
        // Refresh AI plans to show updated data
        await _controller.refreshAiPlans();
      } else {
        await _controller.updateManualPlan(id, payload);
        // Refresh manual plans to show updated data
        await _controller.refreshManualPlans();
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Plan'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            
            // Exercise Plan Category
            _buildFieldLabel('Exercise Plan Category'),
            TextFormField(
              controller: _categoryCtrl,
              style: const TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                hintText: 'Enter exercise plan category',
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
              readOnly: _categoryLocked,
            ),
            const SizedBox(height: 16),
            
            // Date range
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Start Date'),
                      _date('Start date', _start, (d) => setState(() => _start = d)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('End Date'),
                      _date('End date', _end, (d) => setState(() => _end = d)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFieldLabel('User Level'),
            TextFormField(
              controller: _userLevelCtrl,
              style: const TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                hintText: 'e.g., Beginner, Intermediate, Advanced',
                hintStyle: const TextStyle(color: AppTheme.textColor),
                border: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
                filled: true,
                fillColor: AppTheme.cardBackgroundColor,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Exercises'),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final ex = entry.value;
              return _exerciseEditor(idx, ex);
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _items.add({
                      'workout_name': '',
                      'exercise_types': '',
                      'sets': 0,
                      'reps': 0,
                      'weight_kg': 0,
                      'minutes': 0,
                    });
                    // Note: Total exercises is now a separate field, not auto-calculated
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: AppTheme.textColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Exercise'),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _date(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
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
              value.toIso8601String().split('T').first,
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

}

Widget _numField({required String hint, required String initial, required ValueChanged<String> onChanged}) {
  final controller = TextEditingController(text: initial);
  return TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    style: const TextStyle(color: AppTheme.textColor),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textColor),
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
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    onChanged: onChanged,
  );
}

extension on _EditPlanPageState {
  Widget _exerciseEditor(int index, Map<String, dynamic> ex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Exercise ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _items.removeAt(index);
                    // Note: Total exercises is now a separate field, not auto-calculated
                  });
                },
              )
            ],
          ),
          const SizedBox(height: 12),
          
          // Workout Name
          _buildFieldLabel('Workout Name'),
          TextFormField(
            initialValue: ex['workout_name']?.toString() ?? '',
            style: const TextStyle(color: AppTheme.textColor),
            decoration: InputDecoration(
              hintText: 'Enter workout name',
              hintStyle: const TextStyle(color: AppTheme.textColor),
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
            ),
            onChanged: (v) => ex['workout_name'] = v,
          ),
          const SizedBox(height: 12),
          _buildFieldLabel('Exercise Types (e.g., 6)'),
          TextFormField(
            initialValue: ex['exercise_types']?.toString() ?? '',
            style: const TextStyle(color: AppTheme.textColor),
            decoration: InputDecoration(
              hintText: 'e.g., 6',
              hintStyle: const TextStyle(color: AppTheme.textColor),
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
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => ex['exercise_types'] = int.tryParse(v) ?? 0,
          ),
          const SizedBox(height: 12),
          
          // Sets and Reps Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Sets'),
                    _numField(
                      hint: 'Sets',
                      initial: ex['sets']?.toString() ?? '0',
                      onChanged: (v) => ex['sets'] = int.tryParse(v) ?? 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Reps'),
                    _numField(
                      hint: 'Reps',
                      initial: ex['reps']?.toString() ?? '0',
                      onChanged: (v) => ex['reps'] = int.tryParse(v) ?? 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Weight Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Weight (kg)'),
                    _numField(
                      hint: 'Weight',
                      initial: ex['weight_kg']?.toString() ?? '0',
                      onChanged: (v) => ex['weight_kg'] = double.tryParse(v) ?? 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 12),
          _buildFieldLabel('Minutes'),
          _numField(
            hint: 'Minutes',
            initial: ex['minutes']?.toString() ?? '0',
            onChanged: (v) => ex['minutes'] = int.tryParse(v) ?? 0,
          ),
        ],
      ),
    );
  }
}


