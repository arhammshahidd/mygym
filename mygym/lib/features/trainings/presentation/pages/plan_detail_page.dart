import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/trainings_controller.dart';

class PlanDetailPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final bool isAi;
  const PlanDetailPage({super.key, required this.plan, this.isAi = false});

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  late final TrainingsController _controller;
  late List<List<Map<String, dynamic>>> _days; // list of days -> list of exercises
  bool _loading = true;
  String? _startStr;
  String? _endStr;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<TrainingsController>();
    _startStr = widget.plan['start_date']?.toString();
    _endStr = widget.plan['end_date']?.toString();

    // Always try to get full plan data to ensure we have complete items
    final id = int.tryParse(widget.plan['id']?.toString() ?? '');
    if (id != null) {
      _fetchFullPlan(id);
    } else {
      // Fallback to plan data if no ID
      final items = List<Map<String, dynamic>>.from(widget.plan['items'] ?? []);
      if (items.isNotEmpty) {
        _rebuildDays(items);
        _loading = false;
      } else {
        _days = List.generate(1, (_) => []);
        _loading = false;
      }
    }
  }

  Future<void> _fetchFullPlan(int id) async {
    try {
      final full = widget.isAi
          ? await _controller.getAiGeneratedPlan(id)
          : await _controller.getManualPlan(id);
      
      print('🔍 Plan Detail - Full plan data: $full');
      print('🔍 Plan Detail - Items: ${full['items']}');
      
      _startStr = full['start_date']?.toString() ?? _startStr;
      _endStr = full['end_date']?.toString() ?? _endStr;
      final items = List<Map<String, dynamic>>.from(full['items'] ?? []);
      
      print('🔍 Plan Detail - Processed items count: ${items.length}');
      if (items.isNotEmpty) {
        print('🔍 Plan Detail - First item: ${items.first}');
      }
      
      _rebuildDays(items);
    } catch (e) {
      print('❌ Plan Detail - Error fetching full plan: $e');
      // Fallback to widget.plan data
      final fallbackItems = List<Map<String, dynamic>>.from(widget.plan['items'] ?? []);
      if (fallbackItems.isNotEmpty) {
        _rebuildDays(fallbackItems);
      } else {
        _days = List.generate(1, (_) => []);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rebuildDays(List<Map<String, dynamic>> items) {
    print('🔍 Plan Detail - Rebuilding days with ${items.length} items');
    
    // Calculate total days from start/end date or use provided total_days
    int totalDays;
    if (_startStr != null && _endStr != null) {
      final start = DateTime.tryParse(_startStr!);
      final end = DateTime.tryParse(_endStr!);
      if (start != null && end != null) {
        totalDays = max(1, end.difference(start).inDays + 1);
      } else {
        totalDays = max(1, (widget.plan['total_days'] ?? 1) as int);
      }
    } else {
      totalDays = max(1, (widget.plan['total_days'] ?? 1) as int);
    }

    print('🔍 Plan Detail - Total days: $totalDays');
    _days = List.generate(totalDays, (_) => []);
    
    if (items.isEmpty) {
      print('🔍 Plan Detail - No items, showing empty days');
      if (mounted) setState(() {});
      return;
    }

    // Calculate total plan minutes
    final totalPlanMinutes = items.fold<int>(0, (sum, item) => 
        sum + (int.tryParse(item['minutes']?.toString() ?? item['training_minutes']?.toString() ?? '0') ?? 0));
    
    print('🔍 Plan Detail - Total plan minutes: $totalPlanMinutes');
    
    // If plan is less than 80 minutes, create multiple workout cards per day
    if (totalPlanMinutes < 80 && items.length > 1) {
      print('🔍 Plan Detail - Using multiple workouts per day');
      _distributeMultipleWorkoutsPerDay(items, totalDays);
    } else {
      print('🔍 Plan Detail - Using standard distribution');
      _distributeStandard(items, totalDays);
    }
    
    // Debug: print final distribution
    for (int i = 0; i < _days.length; i++) {
      print('🔍 Plan Detail - Day ${i + 1}: ${_days[i].length} exercises');
    }
    
    if (mounted) setState(() {});
  }

  void _distributeMultipleWorkoutsPerDay(List<Map<String, dynamic>> items, int totalDays) {
    // Don't shuffle - keep original order for consistency
    final itemsList = List<Map<String, dynamic>>.from(items);
    
    // Create 2 workout cards per day when plan is short
    for (int day = 0; day < totalDays; day++) {
      final workoutsPerDay = 2; // Always 2 workouts per day for short plans
      for (int i = 0; i < workoutsPerDay; i++) {
        final exerciseIndex = (day * workoutsPerDay + i) % itemsList.length;
        _days[day].add(Map<String, dynamic>.from(itemsList[exerciseIndex]));
      }
    }
  }

  void _distributeStandard(List<Map<String, dynamic>> items, int totalDays) {
    final totalItems = items.length;
    // Don't shuffle - keep original order for consistency
    final itemsList = List<Map<String, dynamic>>.from(items);

    // Build per-day targets: start with 1 each, then distribute remaining up to 3
    final counts = List<int>.filled(totalDays, 1);
    if (totalItems >= totalDays) {
      int remaining = totalItems - totalDays;
      int idx = 0;
      while (remaining > 0) {
        if (counts[idx] < 3) {
          counts[idx]++;
          remaining--;
        }
        idx = (idx + 1) % totalDays;
      }
    }

    int cursor = 0;
    for (int day = 0; day < totalDays; day++) {
      final target = counts[day];
      for (int i = 0; i < target; i++) {
        final src = (totalItems >= totalDays)
            ? itemsList[cursor++]
            : itemsList[(cursor++) % totalItems];
        _days[day].add(Map<String, dynamic>.from(src));
        if (totalItems >= totalDays && cursor >= totalItems) break;
      }
      if (totalItems >= totalDays && cursor >= totalItems) break;
    }
  }

  void _shuffle() {
    // Shuffle with constraints: min 1, max 3 per day; fills all days.
    final rnd = Random();
    // Flatten items
    final allExercises = <Map<String, dynamic>>[];
    for (final day in _days) {
      allExercises.addAll(day);
    }
    if (allExercises.isEmpty) return;
    allExercises.shuffle(rnd);
    // Clear and rebuild using same constrained distribution
    for (final d in _days) d.clear();
    _rebuildDays(allExercises);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TRAINING'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2E7D32),
        actions: [
          TextButton(
            onPressed: _shuffle,
            child: const Text('Shuffle'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E7D32)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final itemWidth = (constraints.maxWidth - spacing) / 2;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: List.generate(_days.length, (dayIndex) {
                        final dayExercises = _days[dayIndex];
                        return SizedBox(
                          width: itemWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E7D32)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DAY ${dayIndex + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (dayExercises.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text(
                                          'No exercises',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    )
                                  else ...dayExercises.map((ex) => _exerciseCard(ex)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(Map<String, dynamic> ex) {
    final workoutName = (ex['workout_name'] ?? ex['exercise_name'] ?? ex['name'] ?? 'Exercise').toString();
    final totalExercises = ex['total_exercises'] ?? ex['total_workouts'] ?? 0;
    final sets = ex['sets'] ?? 0;
    final reps = ex['reps'] ?? 0;
    final weight = ex['weight_kg'] ?? ex['weight'] ?? 0;
    final minutes = ex['minutes'] ?? ex['training_minutes'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Exercise Types', style: TextStyle(color: Colors.white, fontSize: 10)),
              Text('${ex['exercise_types'] ?? 'N/A'}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Workout Name', style: TextStyle(color: Colors.white, fontSize: 10)),
              Flexible(child: Text(workoutName, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sets', style: TextStyle(color: Colors.white, fontSize: 10)),
              Text('$sets', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Reps', style: TextStyle(color: Colors.white, fontSize: 10)),
              Text('$reps', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weight/kg', style: TextStyle(color: Colors.white, fontSize: 10)),
              Text('$weight', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Training Minutes', style: TextStyle(color: Colors.white, fontSize: 10)),
              Text('$minutes', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: Colors.white, fontSize: 10)),
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}


