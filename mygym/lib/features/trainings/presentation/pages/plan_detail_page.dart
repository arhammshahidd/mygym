import 'dart:convert';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/schedules_controller.dart';
import '../controllers/plans_controller.dart';

class PlanDetailPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final bool isAi;
  const PlanDetailPage({super.key, required this.plan, this.isAi = false});

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  late final SchedulesController _schedulesController;
  late final PlansController _plansController;
  late List<List<Map<String, dynamic>>> _days; // list of days -> list of exercises
  bool _loading = true;
  String? _startStr;
  String? _endStr;

  @override
  void initState() {
    super.initState();
    try {
      _schedulesController = Get.find<SchedulesController>();
      _plansController = Get.find<PlansController>();
      print('✅ PlanDetailPage - Controllers found');
    } catch (e) {
      print('❌ PlanDetailPage - Controllers not found: $e');
      // Try to create new instances
      _schedulesController = SchedulesController();
      _plansController = PlansController();
      print('✅ PlanDetailPage - Created new controllers');
    }
    
    _startStr = widget.plan['start_date']?.toString();
    _endStr = widget.plan['end_date']?.toString();
    print('🔍 PlanDetailPage - Start date: $_startStr, End date: $_endStr');

    // Always try to get full plan data to ensure we have complete items
    final id = int.tryParse(widget.plan['id']?.toString() ?? '');
    if (id != null) {
      _fetchFullPlan(id);
    } else {
      // Fallback to plan data if no ID with JSON string parsing
      List<Map<String, dynamic>> items = [];
      
      if (widget.plan['items'] is List && (widget.plan['items'] as List).isNotEmpty) {
        items = List<Map<String, dynamic>>.from(widget.plan['items'] as List);
        print('🔍 Plan Detail - Init using items: ${items.length} items');
      } else if (widget.plan['exercises_details'] != null) {
        print('🔍 Plan Detail - Init using exercises_details: ${widget.plan['exercises_details']}');
        
        try {
          if (widget.plan['exercises_details'] is List) {
            items = List<Map<String, dynamic>>.from(widget.plan['exercises_details'] as List);
            print('🔍 Plan Detail - Init using exercises_details as List: ${items.length} items');
          } else if (widget.plan['exercises_details'] is String) {
            final String exercisesJson = widget.plan['exercises_details'] as String;
            print('🔍 Plan Detail - Init parsing exercises_details JSON: $exercisesJson');
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            items = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            print('🔍 Plan Detail - Init parsed exercises_details: ${items.length} items');
          }
        } catch (parseError) {
          print('❌ Plan Detail - Init failed to parse exercises_details: $parseError');
        }
      }

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
      Map<String, dynamic> full;
      
      if (widget.isAi) {
        full = await _plansController.getAiGeneratedPlan(id);
      } else {
        // Check if this plan is from assignments (Schedules tab) or manual plans (Plans tab)
        // Only treat as assignment if assignment_id is explicitly set and not null/empty
        final assignmentId = widget.plan['assignment_id'];
        final webPlanId = widget.plan['web_plan_id'];
        
        if (assignmentId != null && assignmentId.toString().trim().isNotEmpty && assignmentId != 0) {
          print('🔍 Plan Detail - This is an assignment (assignment_id: $assignmentId), fetching assignment details');
          full = await _schedulesController.getAssignmentDetails(assignmentId);
        } else if (webPlanId != null && webPlanId.toString().trim().isNotEmpty && webPlanId != 0) {
          // This might be a plan from assignments that's being viewed from Plans tab
          print('🔍 Plan Detail - Plan has web_plan_id ($webPlanId), checking if it exists in assignments');
          try {
            // Try to find this plan in assignments first
            final assignments = _schedulesController.assignments;
            final matchingAssignment = assignments.firstWhereOrNull(
              (assignment) => assignment['web_plan_id']?.toString() == webPlanId.toString()
            );
            
            if (matchingAssignment != null) {
              print('🔍 Plan Detail - Found matching assignment, using assignment data');
              full = Map<String, dynamic>.from(matchingAssignment);
            } else {
              print('🔍 Plan Detail - No matching assignment found, treating as manual plan');
              // Fall through to manual plan logic
              full = await _handleManualPlan(id);
            }
          } catch (e) {
            print('❌ Plan Detail - Error checking assignments: $e, treating as manual plan');
            // Fall through to manual plan logic
            full = await _handleManualPlan(id);
          }
        } else {
          // This is definitely a manual plan
          full = await _handleManualPlan(id);
        }
      }
      
      print('🔍 Plan Detail - Full plan data: $full');
      print('🔍 Plan Detail - Items: ${full['items']}');
      print('🔍 Plan Detail - Exercises details: ${full['exercises_details']}');
      
      _startStr = full['start_date']?.toString() ?? _startStr;
      _endStr = full['end_date']?.toString() ?? _endStr;
      
      // Handle both items and exercises_details, with JSON string parsing
      List<Map<String, dynamic>> items = [];
      
      if (full['items'] is List && (full['items'] as List).isNotEmpty) {
        items = List<Map<String, dynamic>>.from(full['items'] as List);
        print('🔍 Plan Detail - Using items: ${items.length} items');
      } else if (full['exercises_details'] != null) {
        print('🔍 Plan Detail - Found exercises_details: ${full['exercises_details']}');
        print('🔍 Plan Detail - exercises_details type: ${full['exercises_details'].runtimeType}');
        
        try {
          if (full['exercises_details'] is List) {
            // Already parsed as List
            items = List<Map<String, dynamic>>.from(full['exercises_details'] as List);
            print('🔍 Plan Detail - Using exercises_details as List: ${items.length} items');
          } else if (full['exercises_details'] is String) {
            // Parse JSON string
            final String exercisesJson = full['exercises_details'] as String;
            print('🔍 Plan Detail - Parsing exercises_details JSON string: $exercisesJson');
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            items = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            print('🔍 Plan Detail - Parsed exercises_details: ${items.length} items');
          }
        } catch (e) {
          print('❌ Plan Detail - Failed to parse exercises_details: $e');
          print('❌ Plan Detail - Raw exercises_details: ${full['exercises_details']}');
        }
      }
      
      print('🔍 Plan Detail - Final processed items count: ${items.length}');
      if (items.isNotEmpty) {
        print('🔍 Plan Detail - First item: ${items.first}');
      } else {
        print('⚠️ Plan Detail - No items found, checking if plan has items directly');
        // Fallback: check if the original plan has items or exercises_details
        if (widget.plan['items'] is List && (widget.plan['items'] as List).isNotEmpty) {
          items = List<Map<String, dynamic>>.from(widget.plan['items'] as List);
          print('🔍 Plan Detail - Using original plan items: ${items.length} items');
        } else if (widget.plan['exercises_details'] != null) {
          print('🔍 Plan Detail - Fallback: Using original plan exercises_details');
          try {
            if (widget.plan['exercises_details'] is List) {
              items = List<Map<String, dynamic>>.from(widget.plan['exercises_details'] as List);
              print('🔍 Plan Detail - Using original exercises_details as List: ${items.length} items');
            } else if (widget.plan['exercises_details'] is String) {
              final List<dynamic> parsedList = jsonDecode(widget.plan['exercises_details'] as String);
              items = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              print('🔍 Plan Detail - Using original exercises_details as String: ${items.length} items');
            }
          } catch (e) {
            print('❌ Plan Detail - Failed to parse original exercises_details: $e');
          }
        }
      }
      
      _rebuildDays(items);
    } catch (e) {
      print('❌ Plan Detail - Error fetching full plan: $e');
      // Fallback to widget.plan data with JSON string parsing
      List<Map<String, dynamic>> fallbackItems = [];
      
      if (widget.plan['items'] is List && (widget.plan['items'] as List).isNotEmpty) {
        fallbackItems = List<Map<String, dynamic>>.from(widget.plan['items'] as List);
        print('🔍 Plan Detail - Fallback using items: ${fallbackItems.length} items');
      } else if (widget.plan['exercises_details'] != null) {
        print('🔍 Plan Detail - Fallback using exercises_details: ${widget.plan['exercises_details']}');
        
        try {
          if (widget.plan['exercises_details'] is List) {
            fallbackItems = List<Map<String, dynamic>>.from(widget.plan['exercises_details'] as List);
            print('🔍 Plan Detail - Fallback using exercises_details as List: ${fallbackItems.length} items');
          } else if (widget.plan['exercises_details'] is String) {
            final String exercisesJson = widget.plan['exercises_details'] as String;
            print('🔍 Plan Detail - Fallback parsing exercises_details JSON: $exercisesJson');
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            fallbackItems = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            print('🔍 Plan Detail - Fallback parsed exercises_details: ${fallbackItems.length} items');
          }
        } catch (parseError) {
          print('❌ Plan Detail - Fallback failed to parse exercises_details: $parseError');
        }
      }
      
      if (fallbackItems.isNotEmpty) {
        _rebuildDays(fallbackItems);
      } else {
      _days = List.generate(1, (_) => []);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _handleManualPlan(int id) async {
    print('🔍 Plan Detail - Handling manual plan with ID: $id');
    print('🔍 Plan Detail - Original plan data: ${widget.plan}');
    
    // Check if the original plan already has complete data
    final hasItems = widget.plan['items'] != null && (widget.plan['items'] as List).isNotEmpty;
    final hasExercisesDetails = widget.plan['exercises_details'] != null && 
        ((widget.plan['exercises_details'] is List && (widget.plan['exercises_details'] as List).isNotEmpty) ||
         (widget.plan['exercises_details'] is String && (widget.plan['exercises_details'] as String).trim().isNotEmpty));
    
    if (hasItems || hasExercisesDetails) {
      print('🔍 Plan Detail - Original plan has complete data, using it directly');
      return Map<String, dynamic>.from(widget.plan);
    } else {
      print('🔍 Plan Detail - Original plan lacks data, fetching from backend');
      try {
        final full = await _plansController.getManualPlan(id);
        print('🔍 Plan Detail - Manual plan fetch successful');
        return full;
      } catch (e) {
        print('❌ Plan Detail - Manual plan fetch failed: $e');
        // If manual plan fetch fails, use the original plan data
        print('🔍 Plan Detail - Using original plan data as fallback');
        print('🔍 Plan Detail - Original plan exercises_details: ${widget.plan['exercises_details']}');
        return Map<String, dynamic>.from(widget.plan);
      }
    }
  }

  void _rebuildDays(List<Map<String, dynamic>> items) {
    print('🔍 Plan Detail - Rebuilding days with ${items.length} items');
    print('🔍 Plan Detail - Items data: $items');
    for (int i = 0; i < items.length; i++) {
      print('🔍 Plan Detail - Item $i: ${items[i]}');
    }
    
    // Calculate total days from start/end date or use provided total_days
    int totalDays;
    if (_startStr != null && _endStr != null) {
      final start = DateTime.tryParse(_startStr!);
      final end = DateTime.tryParse(_endStr!);
      if (start != null && end != null) {
        totalDays = max(1, end.difference(start).inDays + 1);
        print('🔍 Plan Detail - Calculated days from dates: $totalDays (start: $_startStr, end: $_endStr)');
      } else {
        totalDays = max(1, (widget.plan['total_days'] ?? 1) as int);
        print('🔍 Plan Detail - Using total_days from plan: $totalDays');
      }
    } else {
      totalDays = max(1, (widget.plan['total_days'] ?? 1) as int);
      print('🔍 Plan Detail - Using total_days from plan (no dates): $totalDays');
    }

    print('🔍 Plan Detail - Total days: $totalDays');
    _days = List.generate(totalDays, (_) => []);
    
    if (items.isEmpty) {
      print('🔍 Plan Detail - No items, showing empty days');
      // Create some test data for debugging
      print('🔍 Plan Detail - Creating test data for debugging...');
      final testItems = [
        {
          'workout_name': 'Test Workout 1',
          'sets': 3,
          'reps': 10,
          'weight_kg': 50,
          'minutes': 30,
          'exercise_types': 'Strength'
        },
        {
          'workout_name': 'Test Workout 2',
          'sets': 3,
          'reps': 12,
          'weight_kg': 40,
          'minutes': 25,
          'exercise_types': 'Cardio'
        }
      ];
      print('🔍 Plan Detail - Using test items: $testItems');
      _rebuildDays(testItems.map((e) => Map<String, dynamic>.from(e)).toList());
      return;
    }

          // Calculate average minutes per workout
          final totalPlanMinutes = items.fold<int>(0, (sum, item) =>
              sum + (int.tryParse(item['minutes']?.toString() ?? item['training_minutes']?.toString() ?? '0') ?? 0));
          final avgMinutes = items.isEmpty ? 0 : (totalPlanMinutes / items.length).floor();

          print('🔍 Plan Detail - Total plan minutes: $totalPlanMinutes, avg: $avgMinutes');

          // If average workout minutes < 80 and multiple items exist, show multiple per day
          if (avgMinutes < 80 && items.length > 1) {
      print('🔍 Plan Detail - Using multiple workouts per day');
      _distributeMultipleWorkoutsPerDay(items, totalDays, avgMinutes.toDouble());
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

  int _applyWorkoutDistributionLogicForPlanDetail(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return 2;
    
    print('🔍 PLAN DETAIL DISTRIBUTION LOGIC - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Plan Detail Workout $i: ${workout['name']} - ${workout['minutes']} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = int.tryParse(workout['minutes']?.toString() ?? workout['training_minutes']?.toString() ?? '0') ?? 0;
      totalMinutes += minutes;
      print('🔍 Plan Detail Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 PLAN DETAIL FINAL Total workout minutes: $totalMinutes');
    print('🔍 PLAN DETAIL FINAL Number of workouts: ${workouts.length}');
    
    // FORCE TEST: Always apply filtering if we have more than 2 workouts
    if (workouts.length > 2) {
      print('🔍 🚨 PLAN DETAIL FORCE TEST: More than 2 workouts detected, applying filtering regardless of minutes');
      print('🔍 🚨 PLAN DETAIL FORCE FILTERED: Showing 2 workouts per day');
      return 2;
    }
    
    // Apply distribution logic
    if (totalMinutes > 80 && workouts.length > 2) {
      // If total minutes > 80 and we have more than 2 workouts, show only 2 workouts
      print('🔍 PLAN DETAIL ✅ APPLYING LOGIC: Total minutes ($totalMinutes) > 80, showing only 2 workouts');
      return 2;
    } else {
      // If total minutes <= 80 or we have 2 or fewer workouts, show all workouts
      print('🔍 PLAN DETAIL ✅ APPLYING LOGIC: Total minutes ($totalMinutes) <= 80 or <= 2 workouts, showing all ${workouts.length} workouts');
      return workouts.length;
    }
  }

  void _distributeMultipleWorkoutsPerDay(List<Map<String, dynamic>> items, int totalDays, double avgMinutes) {
    print('🔍 Plan Detail - _distributeMultipleWorkoutsPerDay called');
    print('🔍 Plan Detail - Items: ${items.length}, Total days: $totalDays, Avg minutes: $avgMinutes');
    
    // Don't shuffle - keep original order for consistency
    final itemsList = List<Map<String, dynamic>>.from(items);

    // Apply the same distribution logic as the main training page
    final int workoutsPerDay = _applyWorkoutDistributionLogicForPlanDetail(itemsList);
    
    print('🔍 Plan Detail - Workouts per day: $workoutsPerDay');

    // If we don't have enough unique exercises for the desired workouts per day, 
    // limit workouts per day to the number of available exercises
    final int actualWorkoutsPerDay = workoutsPerDay > itemsList.length ? itemsList.length : workoutsPerDay;
    print('🔍 Plan Detail - Actual workouts per day: $actualWorkoutsPerDay (limited by ${itemsList.length} available exercises)');

    // Distribute exercises across days, cycling through exercises to fill all days
    int exerciseIndex = 0;
    for (int day = 0; day < totalDays; day++) {
      for (int i = 0; i < actualWorkoutsPerDay; i++) {
        if (itemsList.isNotEmpty) {
          print('🔍 Plan Detail - Day $day, Workout $i: Adding item at index $exerciseIndex');
          _days[day].add(Map<String, dynamic>.from(itemsList[exerciseIndex % itemsList.length]));
          exerciseIndex++;
        }
      }
      print('🔍 Plan Detail - Day $day now has ${_days[day].length} exercises');
    }
  }

  void _distributeStandard(List<Map<String, dynamic>> items, int totalDays) {
    print('🔍 Plan Detail - _distributeStandard called');
    print('🔍 Plan Detail - Items: ${items.length}, Total days: $totalDays');

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
    
    print('🔍 Plan Detail - Distribution counts: $counts');

    int cursor = 0;
    for (int day = 0; day < totalDays; day++) {
      final target = counts[day];
      print('🔍 Plan Detail - Day $day target: $target exercises');
      for (int i = 0; i < target; i++) {
        if (itemsList.isNotEmpty) {
          final src = itemsList[cursor % totalItems];
          print('🔍 Plan Detail - Day $day, Exercise $i: Adding item at cursor ${cursor % totalItems}');
        _days[day].add(Map<String, dynamic>.from(src));
          cursor++;
        }
      }
      print('🔍 Plan Detail - Day $day now has ${_days[day].length} exercises');
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
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('TRAINING'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        actions: [
          TextButton(
            onPressed: _shuffle,
            child: const Text('Shuffle', style: TextStyle(color: AppTheme.textColor)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor),
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
                              color: AppTheme.cardBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryColor),
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
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (dayExercises.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text(
                                          'No exercises',
                                          style: TextStyle(color: AppTheme.textColor),
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
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Exercise Types', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Text('${ex['exercise_types'] ?? 'N/A'}', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Workout Name', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Flexible(child: Text(workoutName, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sets', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Text('$sets', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Reps', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Text('$reps', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weight/kg', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Text('$weight', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Training Minutes', style: TextStyle(color: AppTheme.textColor, fontSize: 10)),
              Text('$minutes', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
        Text(k, style: const TextStyle(color: AppTheme.textColor, fontSize: 10)),
        Text(v, style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}


