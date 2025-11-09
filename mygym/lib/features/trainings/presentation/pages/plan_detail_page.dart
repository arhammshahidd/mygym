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
        // Only treat as assignment if assignment_id is explicitly present.
        final assignmentId = widget.plan['assignment_id'];
        if (assignmentId != null && assignmentId.toString().trim().isNotEmpty && assignmentId != 0) {
          print('🔍 Plan Detail - Detected assignment_id=$assignmentId → loading assignment details');
          full = await _schedulesController.getAssignmentDetails(assignmentId);
        } else {
          // Manual plan: always fetch manual plan details (or use inline data)
          print('🔍 Plan Detail - Treating as MANUAL plan (no assignment_id).');
          full = await _handleManualPlan(id);
        }
      }
      
      print('🔍 Plan Detail - Full plan data: $full');
      print('🔍 Plan Detail - Items: ${full['items']}');
      print('🔍 Plan Detail - Items type: ${full['items'].runtimeType}');
      print('🔍 Plan Detail - Items length: ${full['items'] is List ? (full['items'] as List).length : 'not a list'}');
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
      if (mounted) {
        try {
          setState(() => _loading = false);
        } catch (e) {
          print('⚠️ Plan Detail - setState failed (widget disposed): $e');
        }
      }
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

  /// Normalize minutes and weight fields in items to ensure they're properly extracted from database
  List<Map<String, dynamic>> _normalizeItemsMinutes(List<Map<String, dynamic>> items) {
    return items.map((item) {
      final normalizedItem = Map<String, dynamic>.from(item);
      
      // Extract minutes from various possible field names and formats
      // Try multiple field names in order of preference
      dynamic minutesRaw = item['minutes'] ?? 
                           item['training_minutes'] ?? 
                           item['trainingMinutes'] ?? 
                           item['duration'] ??
                           item['time_minutes'] ??
                           0;
      
      int minutes = 0;
      if (minutesRaw is int) {
        minutes = minutesRaw;
      } else if (minutesRaw is String && minutesRaw.trim().isNotEmpty) {
        // Try parsing as int, remove any non-numeric characters except minus
        final cleaned = minutesRaw.trim().replaceAll(RegExp(r'[^0-9-]'), '');
        minutes = int.tryParse(cleaned) ?? 0;
      } else if (minutesRaw is num) {
        minutes = minutesRaw.toInt();
      } else if (minutesRaw != null && minutesRaw != 0) {
        // Last resort: try converting to string then parsing
        try {
          minutes = int.tryParse(minutesRaw.toString()) ?? 0;
        } catch (e) {
          minutes = 0;
        }
      }
      
      // Normalize weight fields - check multiple possible field names
      normalizedItem['weight_min_kg'] = item['weight_min_kg'] ?? 
                                        item['weight_min'] ?? 
                                        item['min_weight'] ?? 
                                        item['min_weight_kg'];
      normalizedItem['weight_max_kg'] = item['weight_max_kg'] ?? 
                                        item['weight_max'] ?? 
                                        item['max_weight'] ?? 
                                        item['max_weight_kg'];
      normalizedItem['weight_kg'] = item['weight_kg'] ?? 
                                    item['weight'] ?? 
                                    item['weight_kg'];
      
      // Ensure both minutes and training_minutes are set
      normalizedItem['minutes'] = minutes;
      normalizedItem['training_minutes'] = minutes;
      
      // Debug: only log if minutes or weight were extracted or if raw value was non-zero
      if (minutes > 0 || (minutesRaw != null && minutesRaw != 0 && minutesRaw != '0') || 
          normalizedItem['weight_min_kg'] != null || normalizedItem['weight_max_kg'] != null || normalizedItem['weight_kg'] != null) {
        print('🔍 Plan Detail - Normalized item ${item['workout_name'] ?? item['name'] ?? 'Unknown'}: minutes=$minutes, weight_kg=${normalizedItem['weight_kg']}, weight_min_kg=${normalizedItem['weight_min_kg']}, weight_max_kg=${normalizedItem['weight_max_kg']}');
      }
      
      return normalizedItem;
    }).toList();
  }

  void _rebuildDays(List<Map<String, dynamic>> items) {
    // Normalize items first to ensure minutes are properly extracted
    final normalizedItems = _normalizeItemsMinutes(items);
    
    print('🔍 Plan Detail - Rebuilding days with ${normalizedItems.length} items');
    print('🔍 Plan Detail - Items data: $normalizedItems');
    for (int i = 0; i < normalizedItems.length; i++) {
      print('🔍 Plan Detail - Item $i: ${normalizedItems[i]}');
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
      _days = List.generate(totalDays, (_) => []);
      return;
    }

    // Use controller's distribution logic for consistency with active plan view
    // Build a plan map with exercises_details for the controller
    final planForController = Map<String, dynamic>.from(widget.plan);
    planForController['exercises_details'] = normalizedItems;
    if (_startStr != null) planForController['start_date'] = _startStr;
    if (_endStr != null) planForController['end_date'] = _endStr;
    planForController['total_days'] = totalDays;
    
    // Use controller's getDayWorkoutsForDay for each day to ensure consistency
    for (int dayIndex = 0; dayIndex < totalDays; dayIndex++) {
      final dayWorkouts = _plansController.getDayWorkoutsForDay(planForController, dayIndex);
      _days[dayIndex] = dayWorkouts;
      print('🔍 Plan Detail - Day ${dayIndex + 1}: ${dayWorkouts.length} workouts using controller logic');
    }
    
    // Debug: print final distribution
    for (int i = 0; i < _days.length; i++) {
      print('🔍 Plan Detail - Day ${i + 1}: ${_days[i].length} exercises');
    }
    
    if (mounted) {
      try {
        setState(() {});
      } catch (e) {
        print('⚠️ Plan Detail - setState failed (widget disposed): $e');
      }
    }
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
    
    // Apply same limiting logic for both Manual and Assigned Plans
    // Per-day pair rule: evaluate consecutive pair by average pair for this page
    if (workouts.length >= 2) {
      final int m1 = int.tryParse(workouts[0]['minutes']?.toString() ?? workouts[0]['training_minutes']?.toString() ?? '0') ?? 0;
      final int m2 = int.tryParse(workouts[1]['minutes']?.toString() ?? workouts[1]['training_minutes']?.toString() ?? '0') ?? 0;
      final int combined = m1 + m2;
      if (combined > 80) {
        final planType = widget.isAi ? 'Assigned/AI' : 'Manual';
        print('🔍 PLAN DETAIL ✅ LIMIT (combined > 80) [$planType]: 1 workout');
        return 1;
      }
      print('🔍 PLAN DETAIL ✅ LIMIT (combined <= 80): 2 workouts');
      return 2;
    }
    return workouts.isEmpty ? 0 : 1;
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

    // Distribute workouts across days, cycling through workouts to fill all days
    int workoutIndex = 0;
    for (int day = 0; day < totalDays; day++) {
      for (int i = 0; i < actualWorkoutsPerDay; i++) {
        if (itemsList.isNotEmpty) {
          print('🔍 Plan Detail - Day $day, Workout $i: Adding workout at index $workoutIndex');
          _days[day].add(Map<String, dynamic>.from(itemsList[workoutIndex % itemsList.length]));
          workoutIndex++;
        }
      }
      print('🔍 Plan Detail - Day $day now has ${_days[day].length} workouts');
    }
  }

  void _distributeStandard(List<Map<String, dynamic>> items, int totalDays) {
    print('🔍 Plan Detail - _distributeStandard called');
    print('🔍 Plan Detail - Items: ${items.length}, Total days: $totalDays');

    final totalItems = items.length;
    // Don't shuffle - keep original order for consistency
    final itemsList = List<Map<String, dynamic>>.from(items);

    // Apply workout distribution logic to determine workouts per day
    final int workoutsPerDay = _applyWorkoutDistributionLogicForPlanDetail(itemsList);
    print('🔍 Plan Detail - Workouts per day: $workoutsPerDay');

    // Build per-day targets: start with 1 each, then distribute remaining up to workoutsPerDay
    final counts = List<int>.filled(totalDays, 1);
    if (totalItems >= totalDays) {
      int remaining = totalItems - totalDays;
      int idx = 0;
      while (remaining > 0) {
        if (counts[idx] < workoutsPerDay) {
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
      print('🔍 Plan Detail - Day $day target: $target workouts');
      for (int i = 0; i < target; i++) {
        if (itemsList.isNotEmpty) {
          final src = itemsList[cursor % totalItems];
          print('🔍 Plan Detail - Day $day, Workout $i: Adding workout at cursor ${cursor % totalItems}');
        _days[day].add(Map<String, dynamic>.from(src));
          cursor++;
        }
      }
      print('🔍 Plan Detail - Day $day now has ${_days[day].length} workouts');
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

  String _formatExerciseTypes(dynamic exerciseTypes) {
    if (exerciseTypes == null) return 'N/A';
    
    // If it's already a number, format it as "X types"
    if (exerciseTypes is int) {
      return '$exerciseTypes types';
    }
    
    // If it's a string that can be parsed as a number, format it
    if (exerciseTypes is String) {
      final parsed = int.tryParse(exerciseTypes);
      if (parsed != null) {
        return '$parsed types';
      }
      // If it's a descriptive string like "Strength" or "Cardio", return as-is
      return exerciseTypes;
    }
    
    return exerciseTypes.toString();
  }

  String _formatWorkoutName(String rawName) {
    if (rawName.isEmpty) return 'Exercise';
    
    // Capitalize first letter and return
    return rawName.isNotEmpty ? rawName[0].toUpperCase() + rawName.substring(1) : rawName;
  }

  Widget _exerciseCard(Map<String, dynamic> ex) {
    final rawWorkoutName = (ex['workout_name'] ?? ex['exercise_name'] ?? ex['name'] ?? 'Exercise').toString();
    final workoutName = _formatWorkoutName(rawWorkoutName);
    final totalExercises = ex['total_exercises'] ?? ex['total_workouts'] ?? 0;
    final sets = ex['sets'] ?? 0;
    final reps = ex['reps'] ?? 0;
    final weight = ex['weight_kg'] ?? ex['weight'] ?? 0;
    // Properly extract minutes, handling both string and numeric values from database
    final minutesRaw = ex['minutes'] ?? ex['training_minutes'] ?? ex['trainingMinutes'] ?? 0;
    int minutes = 0;
    if (minutesRaw is int) {
      minutes = minutesRaw;
    } else if (minutesRaw is String) {
      minutes = int.tryParse(minutesRaw) ?? 0;
    } else if (minutesRaw is num) {
      minutes = minutesRaw.toInt();
    }
    print('🔍 Plan Detail - _exerciseCard: workout=$workoutName, minutesRaw=$minutesRaw, minutes=$minutes');
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
              Text('${_formatExerciseTypes(ex['exercise_types'])}', style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
              Text(_formatWeightDisplay(ex), style: const TextStyle(color: AppTheme.textColor, fontSize: 10, fontWeight: FontWeight.bold)),
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

  String _formatWeightDisplay(Map<String, dynamic> item) {
    // Safely convert to double, handling both string and numeric inputs
    // Check multiple possible field names for weight
    final weightMinRaw = item['weight_min_kg'] ?? item['weight_min'] ?? item['min_weight'] ?? item['min_weight_kg'];
    final weightMaxRaw = item['weight_max_kg'] ?? item['weight_max'] ?? item['max_weight'] ?? item['max_weight_kg'];
    final weightRaw = item['weight_kg'] ?? item['weight'] ?? 0;
    
    // Check if weight_kg is stored as a string range like "20-40"
    String? parsedRange;
    if (weightRaw != null && weightRaw is String && weightRaw.contains('-')) {
      // weight_kg is stored as a string range (e.g., "20-40")
      final parts = weightRaw.split('-');
      if (parts.length == 2) {
        final minStr = parts[0].trim();
        final maxStr = parts[1].trim();
        final minVal = _safeParseDouble(minStr);
        final maxVal = _safeParseDouble(maxStr);
        if (minVal != null && maxVal != null) {
          parsedRange = '${minVal.toStringAsFixed(0)}-${maxVal.toStringAsFixed(0)}';
        }
      }
    }
    
    final weightMin = _safeParseDouble(weightMinRaw);
    final weightMax = _safeParseDouble(weightMaxRaw);
    final weight = weightRaw is String && weightRaw.contains('-') ? null : _safeParseDouble(weightRaw);
    
    // If weight_kg was a string range, return it directly
    if (parsedRange != null) {
      return parsedRange;
    }
    
    // If we have min and max, show range (even if one is 0)
    if (weightMin != null && weightMax != null) {
      if (weightMin == 0 && weightMax == 0) {
        // Both are 0, check if single weight exists
        if (weight != null && weight > 0) {
          return '${weight.toStringAsFixed(0)}';
        }
        return '0';
      }
      return '${weightMin.toStringAsFixed(0)}-${weightMax.toStringAsFixed(0)}';
    }
    // If we only have min or max, show that with a dash
    else if (weightMin != null && weightMin > 0) {
      return '${weightMin.toStringAsFixed(0)}+';
    }
    else if (weightMax != null && weightMax > 0) {
      return 'up to ${weightMax.toStringAsFixed(0)}';
    }
    // Fallback to single weight value (even if 0, show it)
    else if (weight != null) {
      return '${weight.toStringAsFixed(0)}';
    }
    
    return '0';
  }

  double? _safeParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
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


