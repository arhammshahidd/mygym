import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../stats/presentation/controllers/stats_controller.dart';
import 'plans_controller.dart';
import '../../data/services/manual_training_service.dart';
import '../../data/services/daily_training_service.dart';
import '../../../../shared/services/realtime_service.dart';
import '../../../auth/data/services/auth_service.dart';

class SchedulesController extends GetxController {
  final ManualTrainingService _manualService = ManualTrainingService();
  final DailyTrainingService _dailyTrainingService = DailyTrainingService();
  final RealtimeService _realtime = RealtimeService();
  final AuthService _authService = AuthService();
  final ProfileController _profileController = Get.find<ProfileController>();
  bool _socketSubscribed = false;

  // Schedules-specific data
  final RxBool isLoading = false.obs;
  final RxBool hasLoadedOnce = false.obs;
  final RxList<Map<String, dynamic>> assignments = <Map<String, dynamic>>[].obs;
  
  // Schedules-specific state management
  final RxMap<int, bool> _startedSchedules = <int, bool>{}.obs;
  final Rx<Map<String, dynamic>?> _activeSchedule = Rx<Map<String, dynamic>?>(null);
  final Map<String, bool> _completedWorkouts = {};
  final Map<String, bool> _workoutTimers = {};
  final RxMap<String, int> _currentDay = <String, int>{}.obs;
  
  // Workout tracking state
  final RxMap<String, bool> _workoutStarted = <String, bool>{}.obs;
  final RxMap<String, int> _workoutRemainingMinutes = <String, int>{}.obs;
  final RxMap<String, bool> _workoutCompleted = <String, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    _loadStartedSchedulesFromCache();
    _loadActiveScheduleSnapshot();
    _subscribeToRealtimeUpdates();
    
    // Retry failed submissions on app start
    retryFailedSubmissions();
  }

  @override
  void onClose() {
    _realtime.disconnect();
    super.onClose();
  }

  Future<void> _subscribeToRealtimeUpdates() async {
    if (_socketSubscribed) return;
    
    try {
      _realtime.connectApprovals();
      _realtime.events.listen((data) {
        print('📡 Schedules - Real-time update: $data');
        // Handle real-time updates for schedules
        _handleRealtimeUpdate(data);
      });
      _socketSubscribed = true;
      print('✅ Schedules - Connected to real-time updates');
    } catch (e) {
      print('❌ Schedules - Failed to connect to real-time updates: $e');
    }
  }

  void _handleRealtimeUpdate(Map<String, dynamic> data) {
    // Handle real-time updates specific to schedules
    final planId = data['plan_id'];
    final status = data['status'];
    
    if (planId != null && status != null) {
      // Update assignment status if needed
      final assignmentIndex = assignments.indexWhere((assignment) => 
          assignment['id']?.toString() == planId.toString());
      
      if (assignmentIndex != -1) {
        assignments[assignmentIndex]['approval_status'] = status;
        assignments.refresh();
      }
    }
  }

  Future<void> loadSchedulesData() async {
    try {
      print('🚀 Schedules - Starting loadSchedulesData...');
      isLoading.value = true;
      
      // Ensure profile is loaded
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      print('👤 Schedules - User ID: $userId');
      
      // Test API connectivity
      await _manualService.testApiConnectivity();
      
      // Fetch ONLY assigned training plans from assignments table (Schedules-specific)
      // This should NOT include manual plans created by the user
      if (userId != null) {
        print('📋 Schedules - Fetching ASSIGNED training plans for user ID: $userId...');
        print('📋 Schedules - API Endpoint: /api/trainingPlans/assignments/user/$userId');
        print('📋 Schedules - This should show assigned training plans (not manual plans)');
        print('🔍 DEBUG: Expected to find assignment with user_id: 2 (from database)');
        try {
          final assignmentsRes = await _manualService.getUserAssignments(userId);
          print('📋 Schedules - Assignments result: ${assignmentsRes.length} items');
          
          // DEBUG: Print all assignment data to understand structure
          print('🔍 DEBUG: Total assignments received: ${assignmentsRes.length}');
          for (int i = 0; i < assignmentsRes.length; i++) {
            final assignment = assignmentsRes[i];
            print('🔍 DEBUG Schedules Assignment $i:');
            print('🔍   - Keys: ${assignment.keys.toList()}');
            print('🔍   - Full Data: $assignment');
            print('🔍   - ID: ${assignment['id']}');
            print('🔍   - Name: ${assignment['name']}');
            print('🔍   - Plan Category: ${assignment['exercise_plan_category']}');
            print('🔍   - User ID: ${assignment['user_id']}');
            print('🔍   - Trainer ID: ${assignment['trainer_id']}');
            print('🔍   - Web Plan ID: ${assignment['web_plan_id']}');
            print('🔍   - Status: ${assignment['status']}');
            print('🔍   - Plan Type: ${assignment['plan_type']}');
          }
          
          // Filter to show ONLY truly assigned plans (not manual plans)
          final filteredAssignments = assignmentsRes.where((assignment) {
            // Check if this is a truly assigned plan
            final planType = assignment['plan_type']?.toString().toLowerCase();
            final assignmentId = assignment['assignment_id'];
            final assignedAt = assignment['assigned_at'];
            final assignedBy = assignment['assigned_by'];
            final trainerId = assignment['trainer_id'];
            final webPlanId = assignment['web_plan_id'];
            final status = assignment['status']?.toString().toUpperCase();
            
            // Enhanced check for assigned plans based on database structure
            final isAssigned = assignmentId != null || 
                              assignedAt != null ||
                              assignedBy != null ||
                              trainerId != null || // Has trainer_id (assigned by trainer)
                              webPlanId != null || // Has web_plan_id (from web portal)
                              planType == 'assigned' ||
                              planType == 'ai_generated' ||
                              status == 'PLANNED' || // Status indicates assigned plan
                              status == 'ACTIVE';
            
            // Additional check: exclude manual plans
            // For assigned plans, user_id is the user the plan is assigned TO, not the creator
            final isManualPlan = planType == 'manual' || 
                                (assignment['created_by'] != null && assignment['created_by'] == userId); // Only exclude if created by current user
            
            print('🔍 Schedules - Assignment ${assignment['id']}:');
            print('🔍   - plan_type: $planType');
            print('🔍   - assignment_id: $assignmentId');
            print('🔍   - assigned_at: $assignedAt');
            print('🔍   - assigned_by: $assignedBy');
            print('🔍   - trainer_id: $trainerId');
            print('🔍   - web_plan_id: $webPlanId');
            print('🔍   - status: $status');
            print('🔍   - created_by: ${assignment['created_by']}');
            print('🔍   - user_id: ${assignment['user_id']}');
            print('🔍   - isAssigned: $isAssigned');
            print('🔍   - isManualPlan: $isManualPlan');
            print('🔍   - Will include: ${isAssigned && !isManualPlan}');
            
            if (!isAssigned) {
              print('❌ REJECTED: Not identified as assigned plan');
            }
            if (isManualPlan) {
              print('❌ REJECTED: Identified as manual plan');
            }
            
            return isAssigned && !isManualPlan;
          }).toList();
          
          print('📋 Schedules - Filtered assignments: ${filteredAssignments.length} items (removed ${assignmentsRes.length - filteredAssignments.length} manual plans)');
          
          // Store ONLY truly assigned plans for Schedules tab
          assignments.assignAll(filteredAssignments.map((e) => Map<String, dynamic>.from(e)));
          print('✅ Schedules - Assigned plans list updated: ${assignments.length} items');
        } catch (e) {
          print('❌ Schedules - Error fetching assignments: $e');
          // Fallback: try with user ID 2
          try {
            final fallbackRes = await _manualService.getUserAssignments(2);
            print('🔍 DEBUG: Fallback assignments result: ${fallbackRes.length} items');
            
            // DEBUG: Print fallback assignment data
            for (int i = 0; i < fallbackRes.length; i++) {
              final assignment = fallbackRes[i];
              print('🔍 DEBUG Fallback Assignment $i:');
              print('🔍   - Keys: ${assignment.keys.toList()}');
              print('🔍   - Values: $assignment');
            }
            
            // Filter fallback assignments the same way
            final filteredFallback = fallbackRes.where((assignment) {
              final planType = assignment['plan_type']?.toString().toLowerCase();
              final assignmentId = assignment['assignment_id'];
              final assignedAt = assignment['assigned_at'];
              final assignedBy = assignment['assigned_by'];
              final isAssigned = assignmentId != null || 
                                assignedAt != null ||
                                assignedBy != null ||
                                planType == 'assigned' ||
                                planType == 'ai_generated';
              
              final isManualPlan = planType == 'manual' || 
                                  assignment['created_by'] != null ||
                                  assignment['user_id'] == 2; // Plans created by user 2
              
              return isAssigned && !isManualPlan;
            }).toList();
            
            assignments.assignAll(filteredFallback.map((e) => Map<String, dynamic>.from(e)));
            print('✅ Schedules - Fallback assigned plans loaded: ${assignments.length} items');
          } catch (fallbackError) {
            print('❌ Schedules - Fallback also failed: $fallbackError');
            assignments.clear();
          }
        }
      } else {
        assignments.clear();
        print('⚠️ Schedules - No user ID, clearing assignments');
      }
      
    } catch (e) {
      print('❌ Schedules - Error loading data: $e');
    } finally {
      isLoading.value = false;
      hasLoadedOnce.value = true;
      print('🏁 Schedules - Load completed');
    }
  }

  // Schedules-specific methods
  
  /// Create completion data for a single exercise
  Map<String, dynamic> _createCompletionItem({
    required int itemId,
    required int setsCompleted,
    required int repsCompleted,
    required double weightUsed,
    required int minutesSpent,
    String? notes,
  }) {
    return {
      'item_id': itemId,
      'sets_completed': setsCompleted,
      'reps_completed': repsCompleted,
      'weight_used': weightUsed,
      'minutes_spent': minutesSpent,
      if (notes != null) 'notes': notes,
    };
  }
  
  /// Submit completion data to API
  Future<void> _submitCompletionToAPI({
    required int dailyPlanId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    try {
      print('🔍 Submitting completion to API via DailyTrainingService');
      await _dailyTrainingService.submitCompletion(
        dailyPlanId: dailyPlanId,
        completionData: completionData,
      );
      print('✅ Completion submitted successfully');
    } catch (e) {
      print('❌ Failed to submit completion to API: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> getAssignmentDetails(int assignmentId) async {
    try {
      // Use ManualTrainingService to get the assignment details
      return await _manualService.getAssignmentDetails(assignmentId);
    } catch (e) {
      print('❌ Schedules - Failed to get assignment details for ID $assignmentId: $e');
      // Return a fallback structure
      return {
        'id': assignmentId,
        'assignment_id': assignmentId,
        'exercises_details': [],
        'items': [],
        'error': 'Failed to fetch assignment details: $e',
      };
    }
  }

  void startSchedule(Map<String, dynamic> schedule) async {
    final int? scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) return;
    
    // Check if there's already an active plan (from any tab)
    final existingActivePlan = await _getAnyActivePlan();
    if (existingActivePlan != null) {
      final currentPlanId = int.tryParse(existingActivePlan['id']?.toString() ?? '');
      
      // If trying to start the same plan, just return
      if (currentPlanId == scheduleId) {
        print('ℹ️ SchedulesController - Schedule $scheduleId is already active');
        return;
      }
      
      // Show confirmation dialog to stop current plan
      final shouldStopCurrent = await _showStopCurrentPlanDialog(existingActivePlan);
      if (!shouldStopCurrent) {
        print('❌ SchedulesController - User cancelled starting new schedule');
        return;
      }
      
      // Stop the current active plan from any tab
      print('🛑 SchedulesController - Stopping current active plan $currentPlanId');
      await _stopAnyActivePlan();
    }
    
    _startedSchedules[scheduleId] = true;
    _activeSchedule.value = schedule;
    _currentDay[scheduleId.toString()] = 0;
    
    _persistStartedSchedulesToCache();
    _persistActiveScheduleSnapshot();
  }

  void stopSchedule(Map<String, dynamic> schedule) {
    final int? scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) return;
    
    _startedSchedules[scheduleId] = false;
    if (_activeSchedule.value != null && (_activeSchedule.value!['id']?.toString() ?? '') == scheduleId.toString()) {
      _activeSchedule.value = null;
    }
    
    _persistStartedSchedulesToCache();
    _clearActiveScheduleSnapshotIfStopped();
  }

  bool isScheduleStarted(int scheduleId) {
    return _startedSchedules[scheduleId] ?? false;
  }

  Map<String, dynamic>? get activeSchedule => _activeSchedule.value;

  int getCurrentDay(int scheduleId) {
    return _currentDay[scheduleId.toString()] ?? 0;
  }

  // Workout tracking methods
  void startWorkout(String workoutKey, int totalMinutes) {
    _workoutStarted[workoutKey] = true;
    _workoutRemainingMinutes[workoutKey] = totalMinutes;
    _workoutCompleted[workoutKey] = false;
    
    // Start timer
    _startWorkoutTimer(workoutKey);
  }

  void _startWorkoutTimer(String workoutKey) {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!(_workoutStarted[workoutKey] ?? false)) {
        timer.cancel();
        return;
      }
      
      final remaining = _workoutRemainingMinutes[workoutKey] ?? 0;
      if (remaining <= 1) {
        // Workout completed
        _workoutCompleted[workoutKey] = true;
        _workoutStarted[workoutKey] = false;
        _workoutRemainingMinutes[workoutKey] = 0;
        timer.cancel();

        // Submit single workout completion immediately to stats
        _submitSingleWorkoutCompletion(workoutKey);
        
        // Check if all workouts for the day are completed
        _checkDayCompletion();
      } else {
        _workoutRemainingMinutes[workoutKey] = remaining - 1;
      }
    });
  }

  void _checkDayCompletion() {
    final activeSchedule = _activeSchedule.value;
    if (activeSchedule == null) return;
    
    final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
    final currentDay = getCurrentDay(planId);
    
    // Get all workouts for current day
    final dayWorkouts = _getDayWorkouts(activeSchedule, currentDay);
    final workoutKeys = dayWorkouts.map((workout) => '${planId}_${currentDay}_${workout['name']}').toList();
    
    print('🔍 Checking day completion for plan $planId, day $currentDay');
    print('🔍 Day workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
    print('🔍 Workout keys: $workoutKeys');
    print('🔍 Completed workouts: ${_workoutCompleted.keys.toList()}');
    
    // Check if all workouts are completed
    bool allCompleted = workoutKeys.every((key) => _workoutCompleted[key] ?? false);
    print('🔍 All workouts completed: $allCompleted');
    
    if (allCompleted && workoutKeys.isNotEmpty) {
      print('🎉 Day $currentDay completed! Moving to day ${currentDay + 1}');
      
      // Submit daily training completion to API
      _submitDailyTrainingCompletion(activeSchedule, currentDay, dayWorkouts);
      
      // Move to next day
      final newDay = currentDay + 1;
      _currentDay[planId.toString()] = newDay;
      _persistCurrentDayToCache(planId, newDay);
      
      print('🔍 Day progression: $currentDay → $newDay for plan $planId');
      print('🔍 Current day state: ${_currentDay.value}');
      
      // Clear completed workouts for next day
      for (String key in workoutKeys) {
        _workoutCompleted.remove(key);
        _workoutStarted.remove(key);
        _workoutRemainingMinutes.remove(key);
      }
      
      print('🔍 Moved to day $newDay, cleared workout states');
      
      // Force UI update
      refreshUI();
      
      // Debug: Check what workouts will be shown for the new day
      final newDayWorkouts = _getDayWorkouts(activeSchedule, newDay);
      print('🔍 New day $newDay workouts: ${newDayWorkouts.map((w) => w['name']).toList()}');
    }
  }

  // Public: return today's workouts for the active schedule (if any)
  List<Map<String, dynamic>> getActiveDayWorkouts() {
    final active = _activeSchedule.value;
    if (active == null) return [];
    final planId = int.tryParse(active['id']?.toString() ?? '') ?? 0;
    final currentDay = getCurrentDay(planId);
    return _getDayWorkouts(active, currentDay);
  }

  // Helper: build workout key for a workout item of the active schedule
  String getWorkoutKeyForItem(Map<String, dynamic> item) {
    final active = _activeSchedule.value;
    if (active == null) return '';
    final planId = int.tryParse(active['id']?.toString() ?? '') ?? 0;
    final currentDay = getCurrentDay(planId);
    final name = item['name']?.toString() ?? item['exercise_name']?.toString() ?? 'workout';
    return '${planId}_${currentDay}_${name}';
  }

  // Submit a single workout completion immediately when its timer finishes
  Future<void> _submitSingleWorkoutCompletion(String workoutKey) async {
    try {
      final active = _activeSchedule.value;
      if (active == null) return;
      final planId = int.tryParse(active['id']?.toString() ?? '') ?? 0;

      // Parse workout key: planId_workoutDay_name
      final parts = workoutKey.split('_');
      if (parts.length < 3) return;
      final workoutDay = int.tryParse(parts[1]) ?? 0; // This is the day when workout was started
      final workoutName = parts.sublist(2).join('_');

      final dayWorkouts = _getDayWorkouts(active, workoutDay);
      final workout = dayWorkouts.firstWhere(
        (w) => (w['name']?.toString() ?? w['exercise_name']?.toString() ?? '') == workoutName,
        orElse: () => {},
      );
      if (workout.isEmpty) return;

      final remaining = _workoutRemainingMinutes[workoutKey] ?? 0;
      final totalMinutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
      final actualMinutes = totalMinutes - remaining;

      final completionItem = _createCompletionItem(
        itemId: int.tryParse(workout['id']?.toString() ?? '0') ?? 0,
        setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
        repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
        weightUsed: double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0,
        minutesSpent: actualMinutes,
        notes: 'Completed ${workoutName} (Day ${workoutDay + 1})',
      );

      // Try to submit to API first
      try {
        await _submitCompletionToAPI(
          dailyPlanId: planId,
          completionData: [completionItem],
        );
        print('✅ Successfully submitted single workout completion: $workoutName (Day ${workoutDay + 1})');
      } catch (e) {
        print('⚠️ API submission failed, storing locally: $e');
        // Store locally as fallback
        await _storeWorkoutCompletionLocally(planId, workoutDay, workoutName, completionItem);
      }

      // Always refresh stats (will use local data if API failed)
      try {
        final statsController = Get.find<StatsController>();
        statsController.refreshStats();
      } catch (_) {}
    } catch (e) {
      print('❌ Failed to submit single workout completion: $e');
    }
  }

  // Store workout completion locally as fallback when API fails
  Future<void> _storeWorkoutCompletionLocally(
    int planId, 
    int currentDay, 
    String workoutName, 
    Map<String, dynamic> completionItem
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'local_workout_completions_user_$userId';
      
      // Get existing completions
      final existingJson = prefs.getString(key) ?? '[]';
      final List<dynamic> completions = jsonDecode(existingJson);
      
      // Add new completion
      final completion = {
        'plan_id': planId,
        'day': currentDay,
        'workout_name': workoutName,
        'completion_item': completionItem,
        'timestamp': DateTime.now().toIso8601String(),
        'date': DateTime.now().toIso8601String().split('T').first,
        'retry_count': 0, // Track retry attempts
      };
      
      completions.add(completion);
      
      // Save back to storage
      await prefs.setString(key, jsonEncode(completions));
      print('✅ Stored workout completion locally: $workoutName (Day ${currentDay + 1})');
    } catch (e) {
      print('❌ Failed to store workout completion locally: $e');
    }
  }

  // Retry failed API submissions from local storage
  Future<void> retryFailedSubmissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'local_workout_completions_user_$userId';
      
      final existingJson = prefs.getString(key) ?? '[]';
      final List<dynamic> completions = jsonDecode(existingJson);
      
      for (int i = 0; i < completions.length; i++) {
        final completion = completions[i] as Map<String, dynamic>;
        final retryCount = completion['retry_count'] as int? ?? 0;
        
        if (retryCount < 3) { // Max 3 retries
          try {
            await _submitCompletionToAPI(
              dailyPlanId: completion['plan_id'] as int,
              completionData: [completion['completion_item'] as Map<String, dynamic>],
            );
            
            // Success - remove from local storage
            completions.removeAt(i);
            i--; // Adjust index after removal
            print('✅ Successfully retried and removed local completion');
          } catch (e) {
            // Increment retry count
            completion['retry_count'] = retryCount + 1;
            print('⚠️ Retry failed (attempt ${retryCount + 1}): $e');
          }
        }
      }
      
      // Save updated completions
      await prefs.setString(key, jsonEncode(completions));
    } catch (e) {
      print('❌ Error during retry process: $e');
    }
  }

  List<Map<String, dynamic>> _getDayWorkouts(Map<String, dynamic> plan, int dayIndex) {
    // This should match the logic in _getDayItems
    try {
      Map<String, dynamic> actualPlan = plan;
      if (plan.containsKey('success') && plan.containsKey('data')) {
        actualPlan = plan['data'] ?? {};
      }
      
      List<Map<String, dynamic>> workouts = [];
      
      final exercisesDetails = actualPlan['exercises_details'];
      if (exercisesDetails is List && exercisesDetails.isNotEmpty) {
        workouts = exercisesDetails.cast<Map<String, dynamic>>();
      } else if (exercisesDetails is String) {
        try {
          final List<dynamic> parsed = jsonDecode(exercisesDetails);
          workouts = parsed.cast<Map<String, dynamic>>();
        } catch (e) {
          return [];
        }
      }
      
      // Calculate total days from start/end date or use provided total_days
      int totalDays = 1;
      if (actualPlan['start_date'] != null && actualPlan['end_date'] != null) {
        final start = DateTime.tryParse(actualPlan['start_date']);
        final end = DateTime.tryParse(actualPlan['end_date']);
        if (start != null && end != null) {
          totalDays = max(1, end.difference(start).inDays + 1);
        }
      } else {
        totalDays = max(1, (actualPlan['total_days'] ?? 1) as int);
      }
      
      print('🔍 Schedules - _getDayWorkouts: Day $dayIndex of $totalDays total days');
      print('🔍 Schedules - Total workouts available: ${workouts.length}');
      
      if (workouts.isEmpty) {
        return [];
      }
      
      // Distribute workouts across days properly
      return _distributeWorkoutsAcrossDays(workouts, totalDays, dayIndex);
      
    } catch (e) {
      print('❌ Schedules - Error in _getDayWorkouts: $e');
      return [];
    }
  }


  List<Map<String, dynamic>> _distributeWorkoutsAcrossDays(List<Map<String, dynamic>> workouts, int totalDays, int dayIndex) {
    if (workouts.isEmpty) return [];
    
    print('🔍 Schedules - _distributeWorkoutsAcrossDays: ${workouts.length} workouts across $totalDays days, requesting day $dayIndex');
    
    // If only one workout, return it for all days
    if (workouts.length == 1) {
      final single = Map<String, dynamic>.from(workouts.first);
      print('🔍 Schedules - Only one workout available: ${single['name']}');
      return [single];
    }

    // Day-based distribution using rotation offset for ALL cases (same as backend)
    // Backend: dayRotationOffset = ((day - 1) * workoutsPerDay) % exercises.length
    // Frontend: dayRotationOffset = (dayIndex * workoutsPerDay) % workouts.length (0-based dayIndex)
    // Rotation always applies for all cases (as per backend fix)
    const int workoutsPerDay = 2;
    final int dayRotationOffset = (dayIndex * workoutsPerDay) % workouts.length;
    final int firstIdx = dayRotationOffset;
    final int secondIdx = (dayRotationOffset + 1) % workouts.length;
    
    final Map<String, dynamic> first = Map<String, dynamic>.from(workouts[firstIdx]);
    final Map<String, dynamic> second = Map<String, dynamic>.from(workouts[secondIdx]);
    final int m1 = _extractWorkoutMinutes(first);
    final int m2 = _extractWorkoutMinutes(second);
    final int combined = m1 + m2;
    
    print('🔍 Schedules - dayRotationOffset: $dayRotationOffset (dayIndex: $dayIndex, workoutsPerDay: $workoutsPerDay, totalWorkouts: ${workouts.length})');
    print('🔍 Schedules - Pair indices: $firstIdx & $secondIdx → ${first['name']}($m1) + ${second['name']}($m2) = $combined');
    
    List<Map<String, dynamic>> selectedWorkouts = [];
    
    // Apply 80-minute rule: if pair exceeds 80 minutes, show only first
    selectedWorkouts = combined > 80 ? [first] : [first, second];

    print('🔍 Schedules - Day $dayIndex selected workouts: ${selectedWorkouts.map((w) => w['name']).toList()}');
    return selectedWorkouts;
  }

  List<Map<String, dynamic>> _applyWorkoutDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 ASSIGNED PLANS DISTRIBUTION LOGIC - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Assigned Workout $i: ${workout['name']} - ${_extractWorkoutMinutes(workout)} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = _extractWorkoutMinutes(workout);
      totalMinutes += minutes;
      print('🔍 Assigned Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 ASSIGNED FINAL Total workout minutes: $totalMinutes');
    print('🔍 ASSIGNED FINAL Number of workouts: ${workouts.length}');
    
    // ASSIGNED PLANS: Apply limiting logic (limit to 2 workouts when total >= 80 minutes)
    if (((totalMinutes >= 80) || (workouts.length > 2)) && workouts.length > 1) {
      // If total minutes >= 80 or we have many workouts, show only 1 workout
      print('🔍 ASSIGNED ✅ APPLYING LOGIC: Total minutes ($totalMinutes) >= 80 or >2 workouts, showing only 1 workout');
      final filteredWorkouts = workouts.take(1).toList();
      print('🔍 ASSIGNED ✅ FILTERED: Showing ${filteredWorkouts.length} workouts: ${filteredWorkouts.map((w) => w['name']).toList()}');
      return filteredWorkouts;
    } else {
      // If total minutes < 80 or we have 2 or fewer workouts, show all workouts
      print('🔍 ASSIGNED ✅ APPLYING LOGIC: Total minutes ($totalMinutes) < 80 or <= 2 workouts, showing all ${workouts.length} workouts');
      return workouts;
    }
  }

  // Extract minutes value from varied backend keys; defaults to 0 on failure
  int _extractWorkoutMinutes(Map<String, dynamic> workout) {
    final dynamic raw = workout['minutes'] ?? workout['training_minutes'] ?? workout['trainingMinutes'];
    if (raw == null) return 0;
    final String asString = raw.toString();
    // Handle double/int strings safely
    final double? asDouble = double.tryParse(asString);
    if (asDouble != null) {
      return asDouble.round();
    }
    final int? asInt = int.tryParse(asString);
    return asInt ?? 0;
  }

  bool isWorkoutStarted(String workoutKey) {
    return _workoutStarted[workoutKey] ?? false;
  }

  bool isWorkoutCompleted(String workoutKey) {
    return _workoutCompleted[workoutKey] ?? false;
  }

  int getWorkoutRemainingMinutes(String workoutKey) {
    return _workoutRemainingMinutes[workoutKey] ?? 0;
  }

  // Force UI refresh
  void refreshUI() {
    print('🔄 SchedulesController - Refreshing UI...');
    _currentDay.refresh();
    _workoutStarted.refresh();
    _workoutCompleted.refresh();
    _workoutRemainingMinutes.refresh();
    _activeSchedule.refresh(); // Also refresh active schedule to trigger UI updates
    print('🔄 SchedulesController - UI refresh completed');
  }

  void setCurrentDay(int scheduleId, int day) {
    _currentDay[scheduleId.toString()] = day;
    _persistCurrentDayToCache(scheduleId, day);
  }

  // Persistence methods for schedules
  Future<void> _loadStartedSchedulesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'startedSchedules_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> cache = jsonDecode(data);
        _startedSchedules.clear();
        cache.forEach((key, value) {
          final int? id = int.tryParse(key);
          if (id != null && value is bool) {
            _startedSchedules[id] = value;
          }
        });
        print('📱 Schedules - Loaded started schedules from cache: ${_startedSchedules.value}');
      }
    } catch (e) {
      print('❌ Schedules - Error loading started schedules from cache: $e');
    }
  }

  Future<void> _loadActiveScheduleSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activeSchedule_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> snapshot = jsonDecode(data);
        _activeSchedule.value = snapshot;
        print('📱 Schedules - Loaded active schedule snapshot from cache: ${snapshot['id']}');
      }
    } catch (e) {
      print('❌ Schedules - Error loading active schedule snapshot from cache: $e');
    }
  }

  Future<void> _persistStartedSchedulesToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'startedSchedules_user_$userId';
      // Convert IdentityMap to regular Map for JSON serialization
      final Map<String, dynamic> serializableMap = {};
      _startedSchedules.forEach((key, value) {
        serializableMap[key.toString()] = value;
      });
      await prefs.setString(key, jsonEncode(serializableMap));
      print('💾 Schedules - Persisted started schedules to cache');
    } catch (e) {
      print('❌ Schedules - Error persisting started schedules: $e');
    }
  }

  Future<void> _persistActiveScheduleSnapshot() async {
    if (_activeSchedule.value == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activeSchedule_user_$userId';
      await prefs.setString(key, jsonEncode(_activeSchedule.value));
      print('💾 Schedules - Persisted active schedule snapshot');
    } catch (e) {
      print('❌ Schedules - Error persisting active schedule snapshot: $e');
    }
  }

  Future<void> _clearActiveScheduleSnapshotIfStopped() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activeSchedule_user_$userId';
      await prefs.remove(key);
      print('🗑️ Schedules - Cleared active schedule snapshot');
    } catch (e) {
      print('❌ Schedules - Error clearing active schedule snapshot: $e');
    }
  }

  Future<void> _persistCurrentDayToCache(int scheduleId, int day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'schedule_day_${scheduleId}_user_$userId';
      await prefs.setInt(key, day);
    } catch (e) {
      print('❌ Schedules - Error persisting current day: $e');
    }
  }

  Future<void> _loadCurrentDayFromCache(int scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'schedule_day_${scheduleId}_user_$userId';
      final int? day = prefs.getInt(key);
      if (day != null) {
        _currentDay[scheduleId.toString()] = day;
      }
    } catch (e) {
      print('❌ Schedules - Error loading current day: $e');
    }
  }

  // Submit daily training completion to API
  Future<void> _submitDailyTrainingCompletion(
    Map<String, dynamic> activeSchedule,
    int currentDay,
    List<Map<String, dynamic>> dayWorkouts,
  ) async {
    try {
      final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
      print('📊 Submitting daily training completion for plan $planId, day $currentDay');
      
      // Create completion data for each workout
      final List<Map<String, dynamic>> completionData = [];
      
      for (final workout in dayWorkouts) {
        final workoutKey = '${planId}_${currentDay}_${workout['name']}';
        final remainingMinutes = _workoutRemainingMinutes[workoutKey] ?? 0;
        final totalMinutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
        final actualMinutes = totalMinutes - remainingMinutes;
        
        final completionItem = _createCompletionItem(
          itemId: int.tryParse(workout['id']?.toString() ?? '0') ?? 0,
          setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
          repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
          weightUsed: double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0,
          minutesSpent: actualMinutes,
          notes: 'Completed via Schedules tab - Day ${currentDay + 1}',
        );
        
        completionData.add(completionItem);
      }
      
      if (completionData.isNotEmpty) {
        // Submit to API
        await _submitCompletionToAPI(
          dailyPlanId: planId,
          completionData: completionData,
        );
        
        print('✅ Daily training completion submitted successfully');
        
        // Notify stats controller to refresh
        try {
          final statsController = Get.find<StatsController>();
          statsController.refreshStats();
        } catch (e) {
          print('⚠️ Stats controller not found, skipping stats refresh: $e');
        }
      }
    } catch (e) {
      print('❌ Failed to submit daily training completion: $e');
      // Don't throw error to avoid breaking the workout flow
    }
  }

  // Refresh schedules data
  Future<void> refreshSchedules() async {
    await loadSchedulesData();
  }

  /// Check for active plans from any tab (Plans, Schedules, etc.)
  Future<Map<String, dynamic>?> _getAnyActivePlan() async {
    // Check Schedules tab active plan
    if (_activeSchedule.value != null) {
      print('🔍 SchedulesController - Found active plan in Schedules tab: ${_activeSchedule.value!['id']}');
      return _activeSchedule.value;
    }
    
    // Check Plans tab active plan
    try {
      if (Get.isRegistered<PlansController>()) {
        final plansController = Get.find<PlansController>();
        if (plansController.activePlan != null) {
          print('🔍 SchedulesController - Found active plan in Plans tab: ${plansController.activePlan!['id']}');
          return plansController.activePlan;
        }
      }
    } catch (e) {
      print('⚠️ SchedulesController - Could not check PlansController: $e');
    }
    
    print('🔍 SchedulesController - No active plans found in any tab');
    return null;
  }

  /// Stop active plan from any tab
  Future<void> _stopAnyActivePlan() async {
    // Stop Schedules tab active plan
    if (_activeSchedule.value != null) {
      print('🛑 SchedulesController - Stopping active plan from Schedules tab');
      stopSchedule(_activeSchedule.value!);
    }
    
    // Stop Plans tab active plan
    try {
      if (Get.isRegistered<PlansController>()) {
        final plansController = Get.find<PlansController>();
        if (plansController.activePlan != null) {
          print('🛑 SchedulesController - Stopping active plan from Plans tab');
          plansController.stopPlan(plansController.activePlan!);
        }
      }
    } catch (e) {
      print('⚠️ SchedulesController - Could not stop PlansController plan: $e');
    }
  }

  /// Show confirmation dialog to stop current plan
  Future<bool> _showStopCurrentPlanDialog(Map<String, dynamic> currentPlan) async {
    final planName = currentPlan['exercise_plan_category'] ?? 
                    currentPlan['name'] ?? 
                    'Current Plan';
    
    return await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Stop Current Plan?'),
        content: Text(
          'You already have an active plan: "$planName"\n\n'
          'Only one plan can be active at a time. Do you want to stop the current plan and start the new one?'
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Stop & Start New'),
          ),
        ],
      ),
      barrierDismissible: false,
    ) ?? false;
  }
}
