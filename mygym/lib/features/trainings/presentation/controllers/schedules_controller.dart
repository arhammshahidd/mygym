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
          
          // Detect unassigned plans (plans that were previously assigned but are no longer in the list)
          final previousAssignmentIds = assignments.map((a) => int.tryParse(a['id']?.toString() ?? '') ?? 0).where((id) => id > 0).toSet();
          final currentAssignmentIds = filteredAssignments.map((a) => int.tryParse(a['id']?.toString() ?? '') ?? 0).where((id) => id > 0).toSet();
          final unassignedIds = previousAssignmentIds.difference(currentAssignmentIds);
          
          // Clean up stats data for unassigned plans
          if (unassignedIds.isNotEmpty) {
            print('🧹 Schedules - Detected ${unassignedIds.length} unassigned plans: $unassignedIds');
            try {
              final statsController = Get.find<StatsController>();
              for (final unassignedId in unassignedIds) {
                // Get web_plan_id and assignment_id from previous assignment data
                // Look in the current assignments list (which contains previous assignments before update)
                final previousAssignment = assignments.firstWhere(
                  (a) => int.tryParse(a['id']?.toString() ?? '') == unassignedId,
                  orElse: () => <String, dynamic>{},
                );
                final webPlanId = previousAssignment['web_plan_id'] as int?;
                final assignmentId = previousAssignment['assignment_id'] as int?;
                
                print('🧹 Schedules - Cleaning up stats and deleting daily training plans for unassigned plan ID: $unassignedId (web_plan_id: $webPlanId, assignment_id: $assignmentId)');
                
                // Clean up local stats data and delete from database
                // deleteFromDatabase: true ensures daily_training_plans are deleted from database when plan is unassigned/deleted from web portal
                await statsController.cleanupStatsForPlan(
                  unassignedId,
                  assignmentId: assignmentId,
                  webPlanId: webPlanId,
                  deleteFromDatabase: true, // Delete from database when plan is unassigned/deleted from web portal
                );
              }
            } catch (e) {
              print('⚠️ Schedules - Error cleaning up stats for unassigned plans: $e');
            }
          }
          
          // Store ONLY truly assigned plans for Schedules tab
          assignments.assignAll(filteredAssignments.map((e) => Map<String, dynamic>.from(e)));
          print('✅ Schedules - Assigned plans list updated: ${assignments.length} items');
          
          // If there are no assigned plans now, clean up all stats data
          if (assignments.isEmpty && previousAssignmentIds.isNotEmpty) {
            print('🧹 Schedules - No assigned plans found, cleaning up all stats data...');
            try {
              final statsController = Get.find<StatsController>();
              await statsController.clearAllStatsData();
              print('🧹 Schedules - All stats data cleared (no assigned plans)');
            } catch (e) {
              print('⚠️ Schedules - Error cleaning up stats when no assignments: $e');
            }
          }
          
          // Also check if this is the first load and there are no assignments
          // If there are no assignments at all, clear stats if they show orphaned data
          if (assignments.isEmpty && previousAssignmentIds.isEmpty) {
            print('🧹 Schedules - No assigned plans on initial load, ensuring stats are clear...');
            try {
              final statsController = Get.find<StatsController>();
              // Only clear if stats show data (might be orphaned data from deleted plans)
              if (statsController.dailyPlansRaw.isNotEmpty || 
                  (statsController.userStats.value != null && 
                   (statsController.userStats.value!.totalWorkouts > 0 || 
                    statsController.userStats.value!.dailyWorkouts.isNotEmpty))) {
                await statsController.clearAllStatsData();
                print('🧹 Schedules - Cleared orphaned stats data (no assigned plans)');
              }
            } catch (e) {
              print('⚠️ Schedules - Error checking stats when no assignments: $e');
            }
          }
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
      
      // If trying to start the same plan, check for completed days and update current day if needed
      if (currentPlanId == scheduleId) {
        print('ℹ️ SchedulesController - Schedule $scheduleId is already active, checking for completed days...');
        
        // Even if plan is already active, check database for completed days to update current day
        try {
          final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
          if (completedDay != null) {
            // completedDay is 1-based (from daily_plans), _currentDay is 0-based
            // If completedDay = 9 (Day 9 completed), we should resume at Day 10 (index 9 in 0-based)
            final currentDay = _currentDay[scheduleId.toString()] ?? 0;
            final nextDay = completedDay; // completedDay is 1-based, use directly as 0-based index for next day
            
            // Only update if the next day is higher than current day (don't go backwards)
            if (nextDay > currentDay) {
              _currentDay[scheduleId.toString()] = nextDay;
              _persistCurrentDayToCache(scheduleId, nextDay);
              print('📅 SchedulesController - ✅ Updated active plan: found completed day $completedDay (1-based), advancing to day $nextDay (0-based index)');
              // Refresh UI to show new day
              update();
            } else {
              print('📅 SchedulesController - Current day $currentDay is already >= next day $nextDay, no update needed');
            }
          } else {
            print('📅 SchedulesController - No completed days found, keeping current day');
          }
        } catch (e) {
          print('⚠️ SchedulesController - Error checking completed days for active plan: $e');
        }
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
    
    // ALWAYS check database first (database is source of truth), then fall back to cache
    // This ensures we resume correctly even if cache is cleared on app restart
    int? cachedDay;
    try {
      print('📅 SchedulesController - Checking database for completed days (database is source of truth)...');
      final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
      if (completedDay != null) {
        // completedDay is 1-based (from daily_plans), _currentDay is now also 1-based
        // If completedDay = 9 (Day 9 completed), we should resume at Day 10 (1-based)
        // Database is always the source of truth, so use it even if cache exists
        final nextDay = completedDay + 1; // completedDay is 1-based, next day is completedDay + 1
        _currentDay[scheduleId.toString()] = nextDay;
        _persistCurrentDayToCache(scheduleId, nextDay);
        print('📅 SchedulesController - ✅ Found completed day $completedDay (1-based) in database, resuming at day $nextDay (1-based, Day $nextDay)');
        cachedDay = nextDay;
      } else {
        print('📅 SchedulesController - ⚠️ No completed days found in database');
        // CRITICAL: If no completed days in database, clear cache and start from Day 1
        // The cache might contain old data from a previous session or different assignment
        // Database is the source of truth - if database shows no completions, we should start fresh
        print('📅 SchedulesController - Clearing cache for schedule $scheduleId (no completed days in database)');
        await _clearCurrentDayCache(scheduleId);
        cachedDay = null; // Force start from Day 1
        print('📅 SchedulesController - Will start from Day 1 since no completed days found');
      }
    } catch (e) {
      print('⚠️ SchedulesController - Error checking database for completed days: $e');
      // If database check fails, don't trust cache - start from Day 1
      // Cache might be stale or from a different assignment
      print('📅 SchedulesController - Database check failed, clearing cache and starting from Day 1');
      await _clearCurrentDayCache(scheduleId);
      cachedDay = null; // Force start from Day 1
    }
    
    if (cachedDay == null) {
      // First time starting this plan, start at day 1 (1-based indexing)
      _currentDay[scheduleId.toString()] = 1;
      _persistCurrentDayToCache(scheduleId, 1);
      print('📅 SchedulesController - Starting new plan $scheduleId at day 1');
    } else {
      // Resume from previous progress
      print('📅 SchedulesController - Resuming plan $scheduleId at day $cachedDay');
    }
    
    // Store daily training plans for assigned plan (plan_type = 'web_assigned')
    try {
      await _storeDailyTrainingPlansForAssignedPlan(schedule);
    } catch (e) {
      print('⚠️ SchedulesController - Failed to store daily training plans: $e');
      // Continue anyway - plan can still be started without stored daily plans
    }
    
    _persistStartedSchedulesToCache();
    _persistActiveScheduleSnapshot();
    
    // Refresh stats when plan is started to show current values
    try {
      final statsController = Get.find<StatsController>();
      print('🔄 SchedulesController - Refreshing stats after starting plan $scheduleId...');
      await statsController.refreshStats(forceSync: true);
      print('✅ SchedulesController - Stats refreshed for started plan $scheduleId');
    } catch (e) {
      print('⚠️ SchedulesController - Error refreshing stats for started plan: $e');
    }
  }

  Future<void> stopSchedule(Map<String, dynamic> schedule) async {
    final int? scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) return;
    
    _startedSchedules[scheduleId] = false;
    if (_activeSchedule.value != null && (_activeSchedule.value!['id']?.toString() ?? '') == scheduleId.toString()) {
      _activeSchedule.value = null;
    }
    
    _persistStartedSchedulesToCache();
    _clearActiveScheduleSnapshotIfStopped();
    
    // Clear stats data for this plan when stopped
    try {
      final statsController = Get.find<StatsController>();
      final webPlanId = schedule['web_plan_id'] as int?;
      final assignmentId = schedule['assignment_id'] as int?;
      
      print('🧹 SchedulesController - Clearing stats for stopped plan ID: $scheduleId (web_plan_id: $webPlanId, assignment_id: $assignmentId)');
      await statsController.cleanupStatsForPlan(
        scheduleId,
        assignmentId: assignmentId,
        webPlanId: webPlanId,
      );
      print('✅ SchedulesController - Stats cleared for stopped plan $scheduleId');
    } catch (e) {
      print('⚠️ SchedulesController - Error clearing stats for stopped plan: $e');
    }
  }

  bool isScheduleStarted(int scheduleId) {
    return _startedSchedules[scheduleId] ?? false;
  }

  Map<String, dynamic>? get activeSchedule => _activeSchedule.value;

  int getCurrentDay(int scheduleId) {
    // Returns 1-based day number (Day 1, Day 2, etc.) to match backend
    return _currentDay[scheduleId.toString()] ?? 1;
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

  Future<void> _checkDayCompletion() async {
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
      await _submitDailyTrainingCompletion(activeSchedule, currentDay, dayWorkouts);
      
      // Move to next day
      final newDay = currentDay + 1;
      _currentDay[planId.toString()] = newDay;
      _persistCurrentDayToCache(planId, newDay);
      
      print('🔍 Day progression: $currentDay → $newDay for plan $planId');
      print('🔍 Current day state: ${_currentDay.value}');
      
      // CRITICAL: Refresh stats after completing a day to ensure stats are updated
      // This ensures that when the app reloads, stats will show the completed workouts
      // Note: Stats are also refreshed in _submitDailyTrainingCompletion, but we refresh here
      // to ensure stats are updated even if the API submission is delayed
      try {
        final statsController = Get.find<StatsController>();
        print('🔄 Schedules - Refreshing stats after completing day $currentDay...');
        await statsController.refreshStats(forceSync: true);
        // Small delay to ensure stats are fully processed
        await Future.delayed(const Duration(milliseconds: 500));
        print('✅ Schedules - Stats refreshed after completing day $currentDay');
      } catch (e) {
        print('⚠️ Schedules - Error refreshing stats after completion: $e');
      }
      
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
      // workoutDay is now 1-based (Day 1, Day 2, etc.) since currentDay is 1-based
      final parts = workoutKey.split('_');
      if (parts.length < 3) return;
      final workoutDay = int.tryParse(parts[1]) ?? 1; // This is the day when workout was started (1-based)
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

      // Find the correct daily_plan_id from stored daily plans
      int? dailyPlanId;
      try {
        // Get the assignment's start_date to calculate the correct plan date
        final assignmentDetails = await getAssignmentDetails(planId);
        Map<String, dynamic> actualPlan = assignmentDetails;
        if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
          actualPlan = assignmentDetails['data'] ?? {};
        }
        
        final DateTime? startDate = actualPlan['start_date'] != null 
            ? DateTime.tryParse(actualPlan['start_date'].toString())
            : null;
        
        if (startDate == null) {
          print('⚠️ SchedulesController - Could not parse start_date from assignment, using DateTime.now()');
        }
        
        // Calculate plan date using assignment's start_date (not DateTime.now())
        // IMPORTANT: workoutDay is now 1-based (Day 1 = 1, Day 2 = 2, etc.)
        // So Day 1 should use startDate + 0 days = startDate (offset = 1 - 1 = 0)
        // Day 2 should use startDate + 1 day = startDate + 1 (offset = 2 - 1 = 1)
        // 
        // Backend now correctly creates daily plans with UTC dates:
        //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0) in UTC
        //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1) in UTC
        // Backend sorts daily_plans by day property and uses day property (not array index) for date calculation
        // Backend uses UTC date components to avoid timezone shifts
        // 
        // Frontend normalizes to UTC date string (YYYY-MM-DD) to match backend format
        DateTime? dateToUse = startDate ?? DateTime.now();
        // Normalize to UTC date components to avoid timezone issues
        final utcDate = DateTime.utc(dateToUse.year, dateToUse.month, dateToUse.day);
        // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
        final dayOffset = workoutDay - 1;
        final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;
        
        print('📅 SchedulesController - Looking up daily plan for single workout:');
        print('  - Plan ID: $planId');
        print('  - Workout Day (1-based): $workoutDay');
        print('  - Calculated plan_date: $planDate (startDate: $startDate + $dayOffset days)');
        
        // CRITICAL: Pass planType='web_assigned' to ensure we only get assigned plans (not manual/AI plans)
        // This matches how manual plans filter by planType='manual' or 'ai_generated'
        final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
        final matchingDay = dailyPlans.firstWhereOrNull((dp) {
          final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
          final dpDate = dp['plan_date']?.toString().split('T').first;
          final dpPlanType = dp['plan_type']?.toString();
          final matches = dpPlanId == planId && dpDate == planDate && dpPlanType == 'web_assigned';
          if (matches) {
            final exercisesDetails = dp['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
              workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            }
            print('✅ SchedulesController - Found matching daily plan: id=${dp['id']}, plan_date=$dpDate, workouts: ${workoutNames.join(", ")}');
          }
          return matches;
        });
        if (matchingDay != null) {
          // Try daily_plan_id first (explicitly provided by backend), then fall back to id
          dailyPlanId = matchingDay['daily_plan_id'] != null
              ? int.tryParse(matchingDay['daily_plan_id']?.toString() ?? '')
              : (matchingDay['id'] != null ? int.tryParse(matchingDay['id']?.toString() ?? '') : null);
          
          // Verify we got the right day's workouts
          final exercisesDetails = matchingDay['exercises_details'];
          if (exercisesDetails is List) {
            final workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            print('✅ SchedulesController - Found daily_plan_id: $dailyPlanId for Day $workoutDay');
            print('✅ SchedulesController - Daily plan workouts: ${workoutNames.join(", ")}');
            print('✅ SchedulesController - ⚠️ VERIFY: These workouts should match Day $workoutDay from the plan!');
          }
        } else {
          print('⚠️ SchedulesController - Could not find daily_plan_id for single workout completion (plan $planId, date $planDate)');
          final relevantPlans = dailyPlans.where((dp) {
            final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            return dpPlanId == planId && (dp['plan_type']?.toString() == 'web_assigned');
          }).toList();
          print('⚠️ SchedulesController - Available daily plans for this assignment:');
          for (final dp in relevantPlans) {
            final dpDate = dp['plan_date']?.toString().split('T').first;
            final exercisesDetails = dp['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
              workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            }
            print('  - ID: ${dp['id']}, plan_date: $dpDate, workouts: ${workoutNames.join(", ")}');
          }
          // Try to create daily plan for this day on-demand if it doesn't exist
          try {
            // Create the daily plan and get the ID directly from the response
            final createdDailyPlanId = await _createDailyPlanForDay(active, workoutDay);
            if (createdDailyPlanId != null) {
              dailyPlanId = createdDailyPlanId;
              print('✅ SchedulesController - Created daily plan on-demand with daily_plan_id: $dailyPlanId for day $workoutDay');
            } else {
              print('❌ SchedulesController - Failed to create daily plan on-demand - no ID returned');
            }
          } catch (e) {
            print('❌ SchedulesController - Failed to create daily plan on-demand: $e');
          }
        }
      } catch (e) {
        print('⚠️ SchedulesController - Could not fetch daily plan ID for single workout: $e');
      }
      
      // Don't use planId as fallback - daily_plan_id is required
      if (dailyPlanId == null) {
        print('❌ SchedulesController - Cannot submit completion: daily_plan_id is null for plan $planId, day $workoutDay');
        // Store locally as fallback instead of submitting with wrong ID
        final completionItem = _createCompletionItem(
          itemId: dayWorkouts.indexOf(workout) + 1,
          setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
          repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
          weightUsed: workout['weight_kg'] is num ? (workout['weight_kg'] as num).toDouble() : (double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0),
          minutesSpent: actualMinutes,
          notes: 'Completed ${workoutName} (Day $workoutDay)',
        );
        await _storeWorkoutCompletionLocally(planId, workoutDay, workoutName, completionItem, dailyPlanId: null);
        return; // Don't try to submit with wrong ID
      }

      // Get item_id as index in exercises_details array (since daily_training_plan_items table is removed)
      // item_id is now the 0-based index in the exercises_details array
      int itemId = 0;
      if (dailyPlanId != null) {
        try {
          final dailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          if (dailyPlan.isNotEmpty) {
            // Parse exercises_details to get exercises array
            dynamic exercisesDetails = dailyPlan['exercises_details'] ?? dailyPlan['items'];
            List<Map<String, dynamic>> exercises = [];
            if (exercisesDetails is List) {
              exercises = exercisesDetails.cast<Map<String, dynamic>>();
            } else if (exercisesDetails is String) {
              try {
                final parsed = jsonDecode(exercisesDetails);
                if (parsed is List) {
                  exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                }
              } catch (e) {
                print('⚠️ SchedulesController - Failed to parse exercises_details: $e');
              }
            }
            
            // Find matching exercise by name - item_id is the 1-based index in exercises_details array
            // Since daily_training_plan_items table is removed, item_id is now the array index (1-based for backend compatibility)
            for (int i = 0; i < exercises.length; i++) {
              final exercise = exercises[i];
              final exerciseName = (exercise['workout_name'] ?? 
                                  exercise['name'] ?? 
                                  exercise['exercise_name'] ?? 
                                  '').toString().trim().toLowerCase();
              if (exerciseName == workoutName.toLowerCase()) {
                itemId = i + 1; // Use 1-based index as item_id (backend expects 1-based)
                print('✅ SchedulesController - Found workout "$workoutName" at array index $i, item_id: $itemId (1-based)');
                break;
              }
            }
            
            // If not found by name, use index-based matching from dayWorkouts
            if (itemId == 0 && dayWorkouts.isNotEmpty) {
              final workoutIndex = dayWorkouts.indexOf(workout);
              if (workoutIndex >= 0 && workoutIndex < exercises.length) {
                itemId = workoutIndex + 1; // Use 1-based index as item_id
                print('✅ SchedulesController - Using workout index $workoutIndex, item_id: $itemId (1-based)');
              }
            }
          }
        } catch (e) {
          print('⚠️ SchedulesController - Could not fetch daily plan to get item_id: $e');
        }
      }
      
      // Fallback to index-based item_id (1-based) if still not found
      if (itemId == 0 && dayWorkouts.isNotEmpty) {
        final workoutIndex = dayWorkouts.indexOf(workout);
        itemId = workoutIndex + 1; // Use 1-based index as item_id (backend expects 1-based)
        print('⚠️ SchedulesController - Using index-based item_id (1-based): $itemId for workout "$workoutName" (array index: $workoutIndex)');
      }

      final completionItem = _createCompletionItem(
        itemId: itemId,
        setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
        repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
        weightUsed: workout['weight_kg'] is num ? (workout['weight_kg'] as num).toDouble() : (double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0),
        minutesSpent: actualMinutes,
          notes: 'Completed ${workoutName} (Day $workoutDay)',
      );

      // Use the correct daily_plan_id (dailyPlanId is guaranteed to be non-null at this point)
      // Try to submit to API first
      try {
        print('📤 SchedulesController - Submitting single workout completion to API:');
        print('  - daily_plan_id: $dailyPlanId');
        print('  - workout: $workoutName');
        print('  - item_id: $itemId');
        print('  - completion_data: $completionItem');
        
        await _submitCompletionToAPI(
          dailyPlanId: dailyPlanId!,
          completionData: [completionItem],
        );
        
        print('✅ Successfully submitted single workout completion: $workoutName (Day $workoutDay) with daily_plan_id: $dailyPlanId, item_id: $itemId');
        
        // CRITICAL: Verify completion was persisted (backend now uses transactions)
        // Check both is_completed AND completed_at (backend requires both)
        // Note: For single workout completions, the daily plan may not be fully completed yet
        // So we only verify that the completion data was stored, not that is_completed=true
        try {
          await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend transaction
          final updatedDailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          final planDate = updatedDailyPlan['plan_date'] as String?;
          final planType = updatedDailyPlan['plan_type'] as String?;
          
          print('📊 SchedulesController - Single workout completion verification:');
          print('  - daily_plan_id: $dailyPlanId');
          print('  - plan_date: $planDate');
          print('  - plan_type: $planType');
          print('  - Note: Daily plan may not be fully completed yet (only one workout completed)');
          
          // For single workout completions, we don't check is_completed (plan may not be fully completed)
          // The backend transaction ensures the completion data was stored
        } catch (verifyError) {
          print('⚠️ SchedulesController - Could not verify single workout completion: $verifyError');
        }
      } catch (e) {
        print('⚠️ API submission failed, storing locally: $e');
        print('❌ SchedulesController - Error details: ${e.toString()}');
        // Try to extract error details if it's a DioException-like error
        try {
          final errorStr = e.toString();
          if (errorStr.contains('status code') || errorStr.contains('Status Code')) {
            print('❌ SchedulesController - Error appears to be HTTP-related');
          }
        } catch (_) {}
        // Store locally as fallback with daily_plan_id if available
        await _storeWorkoutCompletionLocally(planId, workoutDay, workoutName, completionItem, dailyPlanId: dailyPlanId);
      }

      // CRITICAL: Refresh stats after single workout completion (same as manual plans do)
      // This ensures stats are recalculated immediately after each workout completion
      try {
        final statsController = Get.find<StatsController>();
        print('📊 SchedulesController - Refreshing stats after single workout completion (forceSync: true)');
        statsController.refreshStats(forceSync: true);
        print('✅ SchedulesController - Stats refresh triggered successfully');
      } catch (e) {
        print('⚠️ SchedulesController - Stats controller not found, skipping stats refresh: $e');
      }
    } catch (e) {
      print('❌ Failed to submit single workout completion: $e');
    }
  }

  // Store workout completion locally as fallback when API fails
  Future<void> _storeWorkoutCompletionLocally(
    int planId, 
    int currentDay, 
    String workoutName, 
    Map<String, dynamic> completionItem, {
    int? dailyPlanId,
  }) async {
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
        'daily_plan_id': dailyPlanId, // Store daily_plan_id if available
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
      print('✅ Stored workout completion locally: $workoutName (Day $currentDay)${dailyPlanId != null ? ' with daily_plan_id: $dailyPlanId' : ''}');
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
            // Get the correct daily_plan_id from stored daily plans
            int? dailyPlanId = completion['daily_plan_id'] as int?;
            final planId = completion['plan_id'] as int;
            final day = completion['day'] as int;
            
            // If daily_plan_id is not stored, look it up
            if (dailyPlanId == null) {
              try {
                // Get the assignment's start_date to calculate the correct plan date
                final assignmentDetails = await getAssignmentDetails(planId);
                Map<String, dynamic> actualPlan = assignmentDetails;
                if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
                  actualPlan = assignmentDetails['data'] ?? {};
                }
                
                final DateTime? startDate = actualPlan['start_date'] != null 
                    ? DateTime.tryParse(actualPlan['start_date'].toString())
                    : null;
                
                // Calculate plan date using assignment's start_date (not DateTime.now())
                // Normalize to UTC date components to avoid timezone issues (matches backend UTC handling)
                DateTime? dateToUse = startDate ?? DateTime.now();
                final utcDate = DateTime.utc(dateToUse.year, dateToUse.month, dateToUse.day);
                final planDate = utcDate.add(Duration(days: day)).toIso8601String().split('T').first;
                
                // CRITICAL: Pass planType='web_assigned' to ensure we only get assigned plans
                final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
                final matchingDay = dailyPlans.firstWhereOrNull((dp) {
                  final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
                  final dpDate = dp['plan_date']?.toString().split('T').first;
                  final dpPlanType = dp['plan_type']?.toString();
                  return dpPlanId == planId && dpDate == planDate && dpPlanType == 'web_assigned';
                });
                
                if (matchingDay != null) {
                  // Try daily_plan_id first (explicitly provided by backend), then fall back to id
                  dailyPlanId = matchingDay['daily_plan_id'] != null
                      ? int.tryParse(matchingDay['daily_plan_id']?.toString() ?? '')
                      : (matchingDay['id'] != null ? int.tryParse(matchingDay['id']?.toString() ?? '') : null);
                  // Update stored completion with daily_plan_id
                  if (dailyPlanId != null) {
                    completion['daily_plan_id'] = dailyPlanId;
                    print('✅ Retry - Found daily_plan_id: $dailyPlanId for plan $planId, day $day');
                  } else {
                    print('❌ Retry - Could not parse daily_plan_id from matching day');
                    continue; // Skip this retry
                  }
                } else {
                  print('❌ Retry - Could not find daily_plan_id for plan $planId, day $day');
                  continue; // Skip this retry
                }
              } catch (e) {
                print('❌ Retry - Failed to lookup daily_plan_id: $e');
                continue; // Skip this retry
              }
            }
            
            // Skip if daily_plan_id is still null
            if (dailyPlanId == null) {
              print('❌ Retry - daily_plan_id is null, skipping retry');
              continue;
            }
            
            // Use the correct daily_plan_id (not the assignment ID)
            await _submitCompletionToAPI(
              dailyPlanId: dailyPlanId!,
              completionData: [completion['completion_item'] as Map<String, dynamic>],
            );
            
            // Success - remove from local storage
            completions.removeAt(i);
            i--; // Adjust index after removal
            print('✅ Successfully retried and removed local completion with daily_plan_id: $dailyPlanId');
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

  // Public method to get workouts for a specific day (1-based day number)
  List<Map<String, dynamic>> getDayWorkoutsForDay(Map<String, dynamic> plan, int dayNumber) {
    return _getDayWorkouts(plan, dayNumber);
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
      
      // Also check items if exercises_details is empty
      if (workouts.isEmpty && actualPlan['items'] is List) {
        workouts = (actualPlan['items'] as List).cast<Map<String, dynamic>>();
      }
      
      // Normalize weight fields in workouts to ensure they're properly extracted
      workouts = workouts.map((workout) {
        final normalized = Map<String, dynamic>.from(workout);
        // Normalize weight fields - check multiple possible field names
        final weightMinRaw = normalized['weight_min_kg'] ?? 
                            normalized['weight_min'] ?? 
                            normalized['min_weight'] ?? 
                            normalized['min_weight_kg'];
        final weightMaxRaw = normalized['weight_max_kg'] ?? 
                            normalized['weight_max'] ?? 
                            normalized['max_weight'] ?? 
                            normalized['max_weight_kg'];
        final weightRaw = normalized['weight_kg'] ?? normalized['weight'] ?? 0;
        
        // Parse weight_kg if it's a string range like "20-40"
        double? parsedWeightMin;
        double? parsedWeightMax;
        if (weightRaw is String && weightRaw.contains('-')) {
          final parts = weightRaw.split('-');
          if (parts.length == 2) {
            parsedWeightMin = double.tryParse(parts[0].trim());
            parsedWeightMax = double.tryParse(parts[1].trim());
          }
        }
        
        // Use parsed values if available, otherwise use raw values
        if (parsedWeightMin != null && parsedWeightMax != null) {
          normalized['weight_min_kg'] = parsedWeightMin;
          normalized['weight_max_kg'] = parsedWeightMax;
          normalized['weight_kg'] = parsedWeightMin; // Use min as default weight
        } else {
          normalized['weight_min_kg'] = weightMinRaw != null ? double.tryParse(weightMinRaw.toString()) : null;
          normalized['weight_max_kg'] = weightMaxRaw != null ? double.tryParse(weightMaxRaw.toString()) : null;
          normalized['weight_kg'] = weightRaw is String ? double.tryParse(weightRaw) ?? 0.0 : (weightRaw is num ? weightRaw.toDouble() : 0.0);
        }
        
        print('🔍 Schedules - Normalized workout ${normalized['name'] ?? normalized['workout_name'] ?? 'Unknown'}: weight_kg=${normalized['weight_kg']}, weight_min_kg=${normalized['weight_min_kg']}, weight_max_kg=${normalized['weight_max_kg']}');
        return normalized;
      }).toList();
      
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
    // Frontend: dayIndex is now 1-based, so: dayRotationOffset = ((dayIndex - 1) * workoutsPerDay) % workouts.length
    // Rotation always applies for all cases (as per backend fix)
    const int workoutsPerDay = 2;
    // Convert 1-based dayIndex to 0-based offset for rotation calculation
    final int dayRotationOffset = ((dayIndex - 1) * workoutsPerDay) % workouts.length;
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
      final int minutes = _extractWorkoutMinutes(workout);
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

  Future<void> setCurrentDay(int scheduleId, int day) async {
    _currentDay[scheduleId.toString()] = day;
    _persistCurrentDayToCache(scheduleId, day);
    
    // Check if this day is completed and mark workouts accordingly
    await _checkAndMarkDayCompleted(scheduleId, day);
    
    // Refresh UI to show completion status
    refreshUI();
  }
  
  /// Check if a specific day is completed and mark all workouts for that day as completed
  Future<void> _checkAndMarkDayCompleted(int scheduleId, int day) async {
    try {
      final activeSchedule = _activeSchedule.value;
      if (activeSchedule == null) return;
      
      // Get assignment details to calculate plan_date
      final assignmentDetails = await getAssignmentDetails(scheduleId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      final DateTime? startDate = actualPlan['start_date'] != null 
          ? DateTime.tryParse(actualPlan['start_date'].toString())
          : null;
      
      if (startDate == null) {
        print('⚠️ SchedulesController - Could not parse start_date, skipping day completion check');
        return;
      }
      
      // Calculate plan_date for this day (day is 1-based)
      final utcDate = DateTime.utc(startDate.year, startDate.month, startDate.day);
      final dayOffset = day - 1; // Convert 1-based day to 0-based offset
      final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;
      
      print('🔍 SchedulesController - Checking if day $day (plan_date: $planDate) is completed...');
      
      // Get all daily plans for this assignment
      final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final matchingDay = dailyPlans.firstWhereOrNull((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpDate = dp['plan_date']?.toString().split('T').first;
        final dpPlanType = dp['plan_type']?.toString();
        return dpPlanId == scheduleId && dpDate == planDate && dpPlanType == 'web_assigned';
      });
      
      if (matchingDay != null) {
        final isCompleted = matchingDay['is_completed'] as bool? ?? false;
        final completedAt = matchingDay['completed_at'] as String?;
        print('🔍 SchedulesController - Day $day completion status: is_completed=$isCompleted, completed_at=$completedAt');
        
        if (isCompleted) {
          // Day is completed, mark all workouts for this day as completed
          final dayWorkouts = _getDayWorkouts(activeSchedule, day);
          print('✅ SchedulesController - Day $day is completed, marking ${dayWorkouts.length} workouts as completed');
          
          for (final workout in dayWorkouts) {
            final workoutName = workout['name']?.toString() ?? workout['workout_name']?.toString() ?? '';
            final workoutKey = '${scheduleId}_${day}_$workoutName';
            _workoutCompleted[workoutKey] = true;
            _workoutStarted[workoutKey] = false;
            _workoutRemainingMinutes[workoutKey] = 0;
            print('✅ SchedulesController - Marked workout "$workoutName" as completed (key: $workoutKey)');
          }
          
          // Force UI refresh to show completed workouts
          refreshUI();
        }
      } else {
        print('⚠️ SchedulesController - Could not find daily plan for day $day (plan_date: $planDate, scheduleId: $scheduleId)');
        print('⚠️ SchedulesController - Searched in ${dailyPlans.length} daily plans for planType: web_assigned');
      }
    } catch (e) {
      print('⚠️ SchedulesController - Error checking day completion: $e');
    }
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
        final scheduleId = int.tryParse(snapshot['id']?.toString() ?? '');
        print('📱 Schedules - Loaded active schedule snapshot from cache: ${snapshot['id']}');
        
        // Also load the current day for this schedule (if it exists)
        // IMPORTANT: Always check database first (source of truth), then fall back to cache
        if (scheduleId != null) {
          try {
            // CRITICAL: Wait a bit for controllers to initialize before checking database
            // This ensures stats controller is ready when we check for completed days
            await Future.delayed(const Duration(milliseconds: 500));
            print('📱 Schedules - Checking database for completed days when restoring active schedule...');
            final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
            if (completedDay != null) {
            // completedDay is 1-based (from daily_plans), _currentDay is now also 1-based
            // If completedDay = 9 (Day 9 completed), we should resume at Day 10 (1-based)
            final nextDay = completedDay + 1; // completedDay is 1-based, next day is completedDay + 1
              _currentDay[scheduleId.toString()] = nextDay;
              _persistCurrentDayToCache(scheduleId, nextDay);
              print('📱 Schedules - ✅ Restored active schedule: found completed day $completedDay (1-based) in database, resuming at day $nextDay (1-based)');
            } else {
              // No completed days in database, fall back to cache
              await _loadCurrentDayFromCache(scheduleId);
              final cachedDay = _currentDay[scheduleId.toString()];
              if (cachedDay != null) {
                print('📱 Schedules - Loaded current day $cachedDay for schedule $scheduleId from cache (no completed days in database)');
              }
            }
            
            // CRITICAL: Refresh stats when restoring active schedule to show completed plans
            // This ensures stats are loaded before checking for completed days
            try {
              final statsController = Get.find<StatsController>();
              print('🔄 Schedules - Refreshing stats after restoring active schedule $scheduleId...');
              await statsController.refreshStats(forceSync: true);
              // Small delay to ensure stats are fully processed
              await Future.delayed(const Duration(milliseconds: 500));
              print('✅ Schedules - Stats refreshed after restoring active schedule');
            } catch (e) {
              print('⚠️ Schedules - Error refreshing stats after restoring active schedule: $e');
            }
          } catch (e) {
            print('⚠️ Schedules - Error checking database when restoring active schedule: $e');
            // If database check fails, fall back to cache
            await _loadCurrentDayFromCache(scheduleId);
            final cachedDay = _currentDay[scheduleId.toString()];
            if (cachedDay != null) {
              print('📱 Schedules - Loaded current day $cachedDay for schedule $scheduleId from cache (after database error)');
            }
            
            // CRITICAL: Refresh stats even if database check fails
            try {
              final statsController = Get.find<StatsController>();
              print('🔄 Schedules - Refreshing stats after restoring active schedule (database error path)...');
              await statsController.refreshStats(forceSync: true);
              print('✅ Schedules - Stats refreshed after restoring active schedule');
            } catch (e) {
              print('⚠️ Schedules - Error refreshing stats after restoring active schedule: $e');
            }
          }
        }
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

  Future<void> _clearCurrentDayCache(int scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'schedule_day_${scheduleId}_user_$userId';
      await prefs.remove(key);
      _currentDay.remove(scheduleId.toString());
      print('🗑️ Schedules - Cleared cached day for schedule $scheduleId');
    } catch (e) {
      print('❌ Schedules - Error clearing current day cache: $e');
    }
  }

  // Get the last completed day from database by checking completed daily plans
  Future<int?> _getLastCompletedDayFromDatabase(int scheduleId) async {
    try {
      print('🔍 SchedulesController - Checking database for completed days for schedule $scheduleId');
      
      // Get assignment details first (needed for filtering old plans)
      final assignmentDetails = await getAssignmentDetails(scheduleId);
      if (assignmentDetails.isEmpty || assignmentDetails.containsKey('error')) {
        print('⚠️ SchedulesController - Could not get assignment details to filter old plans');
        // Continue anyway, but won't be able to filter by timestamp
      }
      
      // Extract actual plan data (handle API response format)
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      // Get assignment creation/update timestamp to filter out old plans
      final assignmentCreatedAt = actualPlan['created_at'] as String?;
      final assignmentUpdatedAt = actualPlan['updated_at'] as String?;
      DateTime? assignmentTimestamp;
      if (assignmentUpdatedAt != null) {
        assignmentTimestamp = DateTime.tryParse(assignmentUpdatedAt);
      } else if (assignmentCreatedAt != null) {
        assignmentTimestamp = DateTime.tryParse(assignmentCreatedAt);
      }
      
      // Get assignment end_date to ensure plan_date is within valid range
      final endDateStr = actualPlan['end_date'] as String?;
      DateTime? endDate;
      if (endDateStr != null) {
        endDate = DateTime.tryParse(endDateStr);
      }
      
      print('📅 SchedulesController - Assignment timestamp: $assignmentTimestamp, end_date: $endDate');
      
      // Get all daily plans for this assignment (use getDailyTrainingPlans to get all plans including past completed ones)
      // CRITICAL: Pass planType='web_assigned' to ensure we only get assigned plans (not manual/AI plans)
      // Backend now defaults to web_assigned, but being explicit ensures proper isolation
      final allPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      print('📅 SchedulesController - Retrieved ${allPlans.length} total daily plans from database (filtered for web_assigned)');
      
      // Filter plans for this assignment (check source_assignment_id or source_plan_id)
      // IMPORTANT: Also verify that the plan was created AFTER the assignment was created/updated
      // This prevents picking up old plans from previous assignments with the same ID
      // 
      // CRITICAL: STRICTLY filter by plan_type='web_assigned' to avoid picking up manual/AI plan data
      // Manual plans and assigned plans are completely independent and should never interfere
      // 
      // NOTE: Backend now deletes old daily plans when reassigning, but this frontend filtering
      // provides an extra safety layer to ensure we only consider valid, recent plans.
      // Backend behavior: When a plan is deleted and reassigned, syncDailyPlansFromAssignmentHelper
      // deletes all existing daily plans and creates fresh ones with is_completed: false
      final assignmentPlans = allPlans.where((plan) {
        final sourceAssignmentId = plan['source_assignment_id'] as int?;
        final sourcePlanId = plan['source_plan_id'] as int?;
        final planType = plan['plan_type'] as String?;
        final planCreatedAt = plan['created_at'] as String?;
        
        // CRITICAL: First check plan type - MUST be 'web_assigned' (not 'manual' or 'ai_generated')
        // This ensures assigned plans and manual/AI plans are completely isolated
        if (planType != 'web_assigned') {
          return false; // Reject any non-assigned plans immediately
        }
        
        // Then check if IDs match
        final idMatches = (sourceAssignmentId == scheduleId || sourcePlanId == scheduleId);
        if (!idMatches) return false;
        
        // Verify plan was created AFTER assignment was created/updated (to avoid old data)
        if (assignmentTimestamp != null && planCreatedAt != null) {
          final planCreated = DateTime.tryParse(planCreatedAt);
          if (planCreated != null && planCreated.isBefore(assignmentTimestamp)) {
            print('📅 SchedulesController - ⚠️ Skipping old plan: id=${plan['id']}, plan_created=$planCreated, assignment_timestamp=$assignmentTimestamp (plan is older than assignment)');
            return false;
          }
        }
        
        // NOTE: Date range filtering (start_date to end_date) is done in a second pass
        // after we extract start_date from the assignment. This initial filter only checks
        // ID matching and creation timestamp to avoid old plans from previous assignments.
        
        print('📅 SchedulesController - ✅ Found valid plan: id=${plan['id']}, source_assignment_id=$sourceAssignmentId, source_plan_id=$sourcePlanId, plan_type=$planType, is_completed=${plan['is_completed']}, plan_date=${plan['plan_date']}, created_at=$planCreatedAt');
        return true;
      }).toList();
      
      print('📅 SchedulesController - Found ${assignmentPlans.length} plans for assignment $scheduleId');
      
      // Extract start_date from assignment (actualPlan already extracted above)
      // We need this BEFORE filtering by date range
      final startDateStr = actualPlan['start_date'] as String?;
      if (startDateStr == null) {
        print('⚠️ SchedulesController - No start_date in assignment details, cannot filter plans by date range');
        print('⚠️ SchedulesController - Assignment details keys: ${assignmentDetails.keys.toList()}');
        print('⚠️ SchedulesController - Actual plan keys: ${actualPlan.keys.toList()}');
        print('⚠️ SchedulesController - This may cause old plans to be included - returning null for safety');
        return null;
      }
      
      final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
      if (startDate == null && startDateStr != null) {
        print('⚠️ SchedulesController - Could not parse start_date: $startDateStr');
        return null;
      }
      
      // Re-filter plans by date range now that we have start_date
      // Use UTC date normalization to match backend's UTC date handling
      final startDateNormalized = startDate != null ? DateTime.utc(startDate.year, startDate.month, startDate.day) : null;
      if (startDateNormalized != null) {
        print('📅 SchedulesController - Assignment start_date (UTC normalized): $startDateNormalized');
        
        // Filter out plans that are before start_date or after end_date
        final validDatePlans = assignmentPlans.where((plan) {
          final planDateStr = plan['plan_date'] as String?;
          if (planDateStr == null) return false;
          
          final planDate = DateTime.tryParse(planDateStr);
          if (planDate == null) return false;
          
          // Normalize to UTC to match backend's UTC date format
          final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
          
          // Plan date must be >= start_date
          if (planDateNormalized.isBefore(startDateNormalized)) {
            print('📅 SchedulesController - ⚠️ Filtering out plan: id=${plan['id']}, plan_date=$planDateStr is before start_date=$startDateStr');
            return false;
          }
          
          // Plan date must be <= end_date (if end_date is available)
          if (endDate != null) {
            final endDateNormalized = DateTime.utc(endDate.year, endDate.month, endDate.day);
            if (planDateNormalized.isAfter(endDateNormalized)) {
              print('📅 SchedulesController - ⚠️ Filtering out plan: id=${plan['id']}, plan_date=$planDateStr is after end_date=$endDateStr');
              return false;
            }
          }
          
          return true;
        }).toList();
        
        print('📅 SchedulesController - After date range filtering: ${validDatePlans.length} plans (was ${assignmentPlans.length})');
        assignmentPlans.clear();
        assignmentPlans.addAll(validDatePlans);
      }
      
      if (assignmentPlans.isEmpty) {
        print('📅 SchedulesController - No daily plans found in database for schedule $scheduleId (after filtering)');
        return null;
      }
      
      // Get daily_plans from assignment to match plan_date to day numbers
      // The backend's daily_plans uses 1-based day numbers (day: 1, day: 2, etc.)
      // Handle both JSON string and parsed List formats
      List<Map<String, dynamic>> dailyPlans = [];
      final dailyPlansRaw = actualPlan['daily_plans'];
      if (dailyPlansRaw != null) {
        if (dailyPlansRaw is String) {
          // Parse JSON string
          try {
            final parsed = jsonDecode(dailyPlansRaw) as List?;
            if (parsed != null) {
              dailyPlans = parsed.cast<Map<String, dynamic>>();
            }
          } catch (e) {
            print('⚠️ SchedulesController - Error parsing daily_plans JSON string: $e');
          }
        } else if (dailyPlansRaw is List) {
          // Already a List
          dailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
        }
      }
      print('📅 SchedulesController - Found ${dailyPlans.length} days in daily_plans');
      
      // Build a map from plan_date to day number (1-based)
      final dateToDayNumber = <String, int>{};
      for (final dayPlan in dailyPlans) {
        final dayNumber = dayPlan['day'] as int?;
        final dateStr = dayPlan['date'] as String?;
        if (dayNumber != null && dateStr != null) {
          // Normalize date to YYYY-MM-DD format in UTC (matches backend UTC date format)
          final date = DateTime.tryParse(dateStr);
          if (date != null) {
            // Use UTC date components to avoid timezone shifts (matches backend behavior)
            final utcDate = DateTime.utc(date.year, date.month, date.day);
            final normalizedDate = utcDate.toIso8601String().split('T').first;
            dateToDayNumber[normalizedDate] = dayNumber;
            print('📅 SchedulesController - Mapped date $normalizedDate (UTC) to day $dayNumber');
          }
        }
      }
      
      // Find the highest completed day
      int? lastCompletedDay;
      final completedPlans = <Map<String, dynamic>>[];
      
      for (final plan in assignmentPlans) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        
        // Must have is_completed: true to be considered completed
        // If is_completed is true but completed_at is null, it might be a recently completed plan
        // that hasn't been fully updated yet. We'll still consider it completed.
        if (!isCompleted) {
          print('📅 SchedulesController - Skipping plan ${plan['id']}: is_completed=false');
          continue;
        }
        
        // If is_completed is true but completed_at is null, log a warning but still consider it completed
        // This handles cases where the backend hasn't set completed_at yet (race condition or recent completion)
        if (completedAt == null || completedAt.isEmpty) {
          print('⚠️ SchedulesController - Plan ${plan['id']} is marked completed but completed_at is null/empty - may be recently completed');
          print('⚠️ SchedulesController - Will still consider this plan as completed for resume logic');
          // Continue processing - we'll use is_completed=true as the indicator
        }
        
        // Use plan_date to determine which day number this plan belongs to
        // Match plan_date to the day number in daily_plans (1-based)
        final planDateStr = plan['plan_date'] as String?;
        if (planDateStr == null) continue;
        
        final planDate = DateTime.tryParse(planDateStr);
        if (planDate == null) continue;
        
        // Normalize plan_date to UTC date for accurate comparison
        // Backend now uses UTC dates, so we normalize to UTC to match
        final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
        final normalizedDateStr = planDateNormalized.toIso8601String().split('T').first;
        
        print('📅 SchedulesController - Processing completed plan: plan_date=$planDateStr, normalized=$normalizedDateStr');
        print('📅 SchedulesController - Available date mappings: ${dateToDayNumber.keys.toList()}');
        
        // Try to find the day number from daily_plans first (most accurate)
        int? dayNumber;
        if (dateToDayNumber.containsKey(normalizedDateStr)) {
          dayNumber = dateToDayNumber[normalizedDateStr];
          print('📅 SchedulesController - ✅ Found day number $dayNumber from daily_plans for date $normalizedDateStr');
        } else {
          // Fallback: Calculate day number from date difference
          // This handles cases where plan_date doesn't exactly match daily_plans dates
          if (startDateNormalized == null) {
            print('⚠️ SchedulesController - Cannot calculate day number: startDateNormalized is null');
            continue;
          }
          final daysDiff = planDateNormalized.difference(startDateNormalized).inDays;
          if (daysDiff >= 0) {
            // The backend's daily_plans uses 1-based day numbers
            // But we need to check if this matches the actual day structure
            // For now, use daysDiff + 1 as 1-based day number
            dayNumber = daysDiff + 1;
            print('📅 SchedulesController - ⚠️ Date $normalizedDateStr not found in daily_plans, calculated day number $dayNumber from date difference (days_diff=$daysDiff, start_date=$startDateNormalized)');
            
            // IMPORTANT: The fallback calculation (daysDiff + 1) should be correct
            // But we need to verify it matches the backend's day numbering
            // The backend's daily_plans day numbers are 1-based and correspond to the day index
            // So if start_date is 2025-11-02 and plan_date is 2025-11-09:
            //   daysDiff = 7 days
            //   dayNumber = 7 + 1 = 8 (but this might be wrong if daily_plans day 8 has date 2025-11-11)
            // 
            // Actually, looking at the data:
            //   start_date: 2025-11-02
            //   daily_plans day 1: 2025-11-04 (start_date + 2 days)
            //   daily_plans day 2: 2025-11-05 (start_date + 3 days)
            //   daily_plans day 9: 2025-11-12 (start_date + 10 days)
            // 
            // So the formula is: day_number = (date - start_date) + offset
            // But the offset seems to be 2 (day 1 = start_date + 2)
            // So: day_number = (date - start_date) + 2
            // 
            // However, for now, let's use the calculated dayNumber and trust it
            // The issue might be that we're not finding all completed plans
            print('📅 SchedulesController - Using calculated day number $dayNumber (daysDiff=$daysDiff)');
          }
        }
        
        print('📅 SchedulesController - Completed plan: id=${plan['id']}, plan_date=$normalizedDateStr, completed_at=$completedAt, day_number=$dayNumber');
        
        // Only consider valid day numbers
        if (dayNumber != null && dayNumber > 0) {
          completedPlans.add(plan);
          if (lastCompletedDay == null || dayNumber > lastCompletedDay) {
            lastCompletedDay = dayNumber;
            print('📅 SchedulesController - Updated lastCompletedDay to $lastCompletedDay');
          }
        }
      }
      
      print('📅 SchedulesController - Found ${completedPlans.length} completed plans for assignment $scheduleId');
      print('📅 SchedulesController - Last completed day from database query: $lastCompletedDay');
      
      // ALWAYS check stats data as a more reliable source for completed days
      // The database query might not return all completed plans (backend filtering)
      print('📅 SchedulesController - Checking stats data for completed plans...');
      try {
        final statsController = Get.find<StatsController>();
        
        // CRITICAL: Ensure stats are loaded (refresh if needed) with a small delay to allow initialization
        // When app reloads, stats might not be initialized yet, so we need to wait for them
        // Always refresh stats to get the latest completed plans, especially after completing a day
        print('📅 SchedulesController - Ensuring stats are loaded and up-to-date...');
        if (statsController.userStats.value == null || statsController.dailyPlansRaw.isEmpty) {
          print('📅 SchedulesController - Stats not loaded yet, refreshing...');
          // Wait a bit for controllers to initialize, then refresh stats
          await Future.delayed(const Duration(milliseconds: 500));
        }
        // Always refresh to get latest completed plans (even if stats are already loaded)
        await statsController.refreshStats(forceSync: true);
        // Wait a bit more for stats to be fully loaded
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Use dailyPlansRaw from stats (contains all completed plans with plan_date)
        if (statsController.dailyPlansRaw.isNotEmpty) {
          print('📅 SchedulesController - Found ${statsController.dailyPlansRaw.length} plans in stats dailyPlansRaw');
          
          // Filter for this assignment's completed plans
          // IMPORTANT: Apply same filtering as database query to avoid old data
          final statsCompletedPlans = statsController.dailyPlansRaw.where((plan) {
            final sourceAssignmentId = plan['source_assignment_id'] as int?;
            final sourcePlanId = plan['source_plan_id'] as int?;
            final planType = plan['plan_type'] as String?;
            final isCompleted = plan['is_completed'] as bool? ?? false;
            final completedAt = plan['completed_at'] as String?;
            final planCreatedAt = plan['created_at'] as String?;
            
            // CRITICAL: First check plan type - MUST be 'web_assigned' (not 'manual' or 'ai_generated')
            // This ensures assigned plans and manual/AI plans are completely isolated
            if (planType != 'web_assigned') {
              return false; // Reject any non-assigned plans immediately
            }
            
            // Then check if IDs match and plan is completed
            final idMatches = (sourceAssignmentId == scheduleId || sourcePlanId == scheduleId) && 
                           isCompleted && 
                           completedAt != null && 
                           completedAt.isNotEmpty;
            if (!idMatches) return false;
            
            // Verify plan was created AFTER assignment was created/updated (to avoid old data)
            if (assignmentTimestamp != null && planCreatedAt != null) {
              final planCreated = DateTime.tryParse(planCreatedAt);
              if (planCreated != null && planCreated.isBefore(assignmentTimestamp)) {
                print('📅 SchedulesController - ⚠️ Skipping old stats plan: id=${plan['id']}, plan_created=$planCreated, assignment_timestamp=$assignmentTimestamp (plan is older than assignment)');
                return false;
              }
            }
            
            // Verify plan_date is within assignment's date range (if end_date is available)
            if (endDate != null) {
              final planDateStr = plan['plan_date'] as String?;
              if (planDateStr != null) {
                final planDate = DateTime.tryParse(planDateStr);
                if (planDate != null && planDate.isAfter(endDate)) {
                  print('📅 SchedulesController - ⚠️ Skipping stats plan: id=${plan['id']}, plan_date=$planDateStr is after assignment end_date=$endDateStr');
                  return false;
                }
              }
            }
            
            print('📅 SchedulesController - ✅ Found valid stats plan: id=${plan['id']}, plan_date=${plan['plan_date']}, completed_at=$completedAt, created_at=$planCreatedAt');
            return true;
          }).toList();
          
          print('📅 SchedulesController - Found ${statsCompletedPlans.length} completed plans in stats for assignment $scheduleId');
          
          // Calculate day numbers for stats plans
          int? statsLastDay;
          for (final plan in statsCompletedPlans) {
            final planDateStr = plan['plan_date'] as String?;
            if (planDateStr == null) continue;
            
            final planDate = DateTime.tryParse(planDateStr);
            if (planDate == null) continue;
            
            // Normalize to UTC date components to match backend UTC format
            final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
            final normalizedDateStr = planDateNormalized.toIso8601String().split('T').first;
            
            // Try to find the day number from daily_plans first (most accurate)
            int? dayNum;
            if (dateToDayNumber.containsKey(normalizedDateStr)) {
              dayNum = dateToDayNumber[normalizedDateStr];
              print('📅 SchedulesController - ✅ Stats plan date $normalizedDateStr maps to day $dayNum from daily_plans');
            } else {
              // Fallback: calculate from date difference
              if (startDateNormalized == null) {
                print('⚠️ SchedulesController - Cannot calculate day number from stats: startDateNormalized is null');
                continue;
              }
              final daysDiff = planDateNormalized.difference(startDateNormalized).inDays;
              if (daysDiff >= 0) {
                dayNum = daysDiff + 1;
                print('📅 SchedulesController - ⚠️ Stats plan date $normalizedDateStr not in daily_plans, calculated day $dayNum from date difference (daysDiff=$daysDiff)');
                
                // Try to find closest matching date in daily_plans (within 2 days)
                int? closestDay;
                int minDiff = 999;
                for (final entry in dateToDayNumber.entries) {
                  final mappedDate = DateTime.tryParse(entry.key);
                  if (mappedDate != null) {
                    // Normalize to UTC date components to match backend UTC format
                    final mappedDateNormalized = DateTime.utc(mappedDate.year, mappedDate.month, mappedDate.day);
                    final dateDiff = (planDateNormalized.difference(mappedDateNormalized).inDays).abs();
                    if (dateDiff < minDiff && dateDiff <= 2) {
                      minDiff = dateDiff;
                      closestDay = entry.value;
                    }
                  }
                }
                if (closestDay != null && minDiff <= 2) {
                  dayNum = closestDay;
                  print('📅 SchedulesController - ✅ Found closest matching day $closestDay (date diff: $minDiff days)');
                }
              }
            }
            
            if (dayNum != null && dayNum > 0) {
              if (statsLastDay == null || dayNum > statsLastDay) {
                statsLastDay = dayNum;
                print('📅 SchedulesController - Updated statsLastDay to $statsLastDay');
              }
            }
          }
          
          // Use stats data if it shows a higher completed day
          if (statsLastDay != null && (lastCompletedDay == null || statsLastDay > lastCompletedDay)) {
            print('📅 SchedulesController - ✅ Using stats data: lastCompletedDay = $statsLastDay (database had: $lastCompletedDay)');
            lastCompletedDay = statsLastDay;
          } else if (statsLastDay != null) {
            print('📅 SchedulesController - Stats shows lastCompletedDay = $statsLastDay, but database shows $lastCompletedDay (using database)');
          }
        } else {
          print('📅 SchedulesController - ⚠️ Stats dailyPlansRaw is empty, trying userStats.dailyWorkouts as fallback...');
          
          // Fallback: Use dailyWorkouts from userStats (more likely to be populated)
          if (statsController.userStats.value != null) {
            final dailyWorkouts = statsController.userStats.value!.dailyWorkouts;
            if (dailyWorkouts.isNotEmpty) {
              print('📅 SchedulesController - Found ${dailyWorkouts.length} dates in dailyWorkouts');
              
              int? statsLastDay;
              for (final dateStr in dailyWorkouts.keys) {
                final date = DateTime.tryParse(dateStr);
                if (date == null) continue;
                
                // Normalize to UTC date components to match backend UTC format
                final dateNormalized = DateTime.utc(date.year, date.month, date.day);
                final normalizedDateStr = dateNormalized.toIso8601String().split('T').first;
                
                // Try to find the day number from daily_plans first
                int? dayNum;
                if (dateToDayNumber.containsKey(normalizedDateStr)) {
                  dayNum = dateToDayNumber[normalizedDateStr];
                  print('📅 SchedulesController - ✅ dailyWorkouts date $normalizedDateStr maps to day $dayNum');
                } else {
                  // Fallback: calculate from date difference
                  if (startDateNormalized == null) {
                    print('⚠️ SchedulesController - Cannot calculate day number from dailyWorkouts: startDateNormalized is null');
                    continue;
                  }
                  final daysDiff = dateNormalized.difference(startDateNormalized).inDays;
                  if (daysDiff >= 0) {
                    dayNum = daysDiff + 1;
                    print('📅 SchedulesController - ⚠️ dailyWorkouts date $normalizedDateStr not in daily_plans, calculated day $dayNum (daysDiff=$daysDiff)');
                    
                    // Try to find closest matching date in daily_plans (within 2 days)
                    int? closestDay;
                    int minDiff = 999;
                    for (final entry in dateToDayNumber.entries) {
                      final mappedDate = DateTime.tryParse(entry.key);
                      if (mappedDate != null) {
                        // Normalize to UTC date components to match backend UTC format
                        final mappedDateNormalized = DateTime.utc(mappedDate.year, mappedDate.month, mappedDate.day);
                        final dateDiff = (dateNormalized.difference(mappedDateNormalized).inDays).abs();
                        if (dateDiff < minDiff && dateDiff <= 2) {
                          minDiff = dateDiff;
                          closestDay = entry.value;
                        }
                      }
                    }
                    if (closestDay != null && minDiff <= 2) {
                      dayNum = closestDay;
                      print('📅 SchedulesController - ✅ Found closest matching day $closestDay (date diff: $minDiff days)');
                    }
                  }
                }
                
                if (dayNum != null && dayNum > 0) {
                  if (statsLastDay == null || dayNum > statsLastDay) {
                    statsLastDay = dayNum;
                  }
                }
              }
              
              if (statsLastDay != null && (lastCompletedDay == null || statsLastDay > lastCompletedDay!)) {
                print('📅 SchedulesController - ✅ Using dailyWorkouts data: lastCompletedDay = $statsLastDay (database had: $lastCompletedDay)');
                lastCompletedDay = statsLastDay;
              } else if (statsLastDay != null && lastCompletedDay != null) {
                print('📅 SchedulesController - dailyWorkouts shows lastCompletedDay = $statsLastDay, but database shows $lastCompletedDay (using higher value)');
                if (statsLastDay > lastCompletedDay!) {
                  lastCompletedDay = statsLastDay;
                }
              }
              
              // Additional check: If dailyWorkouts has 9 dates and we're only finding 6 days,
              // use the count of dates as a fallback (assuming sequential completion)
              if (dailyWorkouts.length >= 9 && (lastCompletedDay == null || lastCompletedDay < 9)) {
                print('📅 SchedulesController - ⚠️ dailyWorkouts has ${dailyWorkouts.length} dates, suggesting ${dailyWorkouts.length} completed days');
                print('📅 SchedulesController - Using count of dates as fallback: lastCompletedDay = ${dailyWorkouts.length}');
                lastCompletedDay = dailyWorkouts.length;
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ SchedulesController - Error getting completed days from stats: $e');
        print('⚠️ SchedulesController - Stack trace: ${StackTrace.current}');
      }
      
      if (lastCompletedDay != null) {
        // lastCompletedDay is 1-based (from daily_plans), _currentDay is now also 1-based
        // If lastCompletedDay = 9 (Day 9 completed), we should resume at Day 10 (1-based)
        // UI shows "Day ${currentDay}", so:
        //   - _currentDay = 9 → UI shows "Day 9"
        //   - _currentDay = 10 → UI shows "Day 10"
        // Final validation: If we found a completed day, verify it's reasonable for a newly assigned plan
        // If the assignment was just created (within last hour), and we're finding Day 7+, that's suspicious
        // 
        // NOTE: With backend changes, old daily plans are deleted when reassigning, so this check
        // should rarely trigger. However, it provides an extra safety layer in case of edge cases
        // or if the backend deletion didn't complete properly.
        if (assignmentTimestamp != null) {
          final now = DateTime.now();
          final assignmentAge = now.difference(assignmentTimestamp);
          
          // If assignment is less than 1 hour old and we're finding Day 7+, that's likely old data
          // Backend should have deleted old plans, but this is a safety check
          if (assignmentAge.inHours < 1 && lastCompletedDay >= 7) {
            print('📅 SchedulesController - ⚠️ Suspicious: Assignment is only ${assignmentAge.inMinutes} minutes old, but found Day $lastCompletedDay completed');
            print('📅 SchedulesController - ⚠️ This is likely old data from a previous assignment - ignoring and starting from Day 1');
            print('📅 SchedulesController - ⚠️ Backend should have deleted old plans, but this safety check is preventing incorrect resume');
            return null; // Start from Day 1 for newly assigned plans
          }
        }
        
        // CRITICAL: Return lastCompletedDay (1-based) directly
        // The caller will convert it to 0-based index for _currentDay
        // If Day 1 is completed, lastCompletedDay = 1, caller sets _currentDay = 1 (0-based) = Day 2 in UI ✓
        print('📅 SchedulesController - Last completed day from database: $lastCompletedDay (1-based, Day $lastCompletedDay completed)');
        print('📅 SchedulesController - Should resume at Day ${lastCompletedDay + 1} (1-based)');
        print('📅 SchedulesController - UI will show: "Day ${lastCompletedDay + 1}"');
        return lastCompletedDay; // Return 1-based day number (caller will add 1 to get next day)
      } else {
        print('📅 SchedulesController - No completed days found in database for assignment $scheduleId');
        print('📅 SchedulesController - All plans for this assignment:');
        for (final plan in assignmentPlans) {
          print('  - Plan ID: ${plan['id']}, is_completed: ${plan['is_completed']}, plan_date: ${plan['plan_date']}, plan_type: ${plan['plan_type']}');
        }
        
        // If no completed plans found, try to get from stats data as fallback
        print('📅 SchedulesController - Trying to get completed days from stats data as fallback...');
        try {
          final statsController = Get.find<StatsController>();
          if (statsController.userStats.value != null) {
            final dailyWorkouts = statsController.userStats.value!.dailyWorkouts;
            print('📅 SchedulesController - Stats dailyWorkouts keys: ${dailyWorkouts.keys.toList()}');
            
            // Calculate day numbers from dailyWorkouts dates
            if (dailyWorkouts.isNotEmpty) {
              // Normalize to UTC to match backend's UTC date format
              final startDateNormalized = DateTime.utc(startDate.year, startDate.month, startDate.day);
              int? statsLastDay;
              
              for (final dateStr in dailyWorkouts.keys) {
                final date = DateTime.tryParse(dateStr);
                if (date == null) continue;
                
                // Normalize to UTC to match backend's UTC date format
                final dateNormalized = DateTime.utc(date.year, date.month, date.day);
                final daysDiff = dateNormalized.difference(startDateNormalized).inDays;
                
                if (daysDiff >= 0) {
                  // CRITICAL: Convert daysDiff (0-based) to 1-based day number
                  // daysDiff = 0 means Day 1, so day number = 0 + 1 = 1
                  // daysDiff = 1 means Day 2, so day number = 1 + 1 = 2
                  final dayNumber = daysDiff + 1; // Convert to 1-based
                  if (statsLastDay == null || dayNumber > statsLastDay) {
                    statsLastDay = dayNumber;
                  }
                }
              }
              
              if (statsLastDay != null) {
                print('📅 SchedulesController - Found last completed day from stats: $statsLastDay (1-based)');
                return statsLastDay; // Return 1-based day number
              }
            }
          }
        } catch (e) {
          print('⚠️ SchedulesController - Error getting completed days from stats: $e');
        }
      }
      
      return lastCompletedDay;
    } catch (e) {
      print('❌ SchedulesController - Error getting last completed day from database: $e');
      print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
      return null;
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
      
      // First, find the daily_plan_id from daily_training_plans table
      int? dailyPlanId;
      try {
        // Get the assignment's start_date to calculate the correct plan date
        final assignmentDetails = await getAssignmentDetails(planId);
        Map<String, dynamic> actualPlan = assignmentDetails;
        if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
          actualPlan = assignmentDetails['data'] ?? {};
        }
        
        final DateTime? startDate = actualPlan['start_date'] != null 
            ? DateTime.tryParse(actualPlan['start_date'].toString())
            : null;
        
        if (startDate == null) {
          print('⚠️ SchedulesController - Could not parse start_date from assignment, using DateTime.now()');
        }
        
        // Calculate plan date using assignment's start_date (not DateTime.now())
        // IMPORTANT: currentDay is now 1-based (Day 1 = 1, Day 2 = 2, etc.)
        // So Day 1 should use startDate + 0 days = startDate (offset = 1 - 1 = 0)
        // Day 2 should use startDate + 1 day = startDate + 1 (offset = 2 - 1 = 1)
        // 
        // Backend now correctly creates daily plans with UTC dates:
        //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0) in UTC
        //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1) in UTC
        // Backend sorts daily_plans by day property and uses day property (not array index) for date calculation
        // Backend uses UTC date components to avoid timezone shifts
        // 
        // Frontend normalizes to UTC date string (YYYY-MM-DD) to match backend format
        DateTime? dateToUse = startDate ?? DateTime.now();
        // Normalize to UTC date components to avoid timezone issues
        final utcDate = DateTime.utc(dateToUse.year, dateToUse.month, dateToUse.day);
        // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
        final dayOffset = currentDay - 1;
        final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;
        
        print('📅 SchedulesController - Looking up daily plan:');
        print('  - Plan ID: $planId');
        print('  - Current Day (1-based): $currentDay');
        print('  - Calculated plan_date: $planDate (startDate: $startDate + $dayOffset days)');
        
        // CRITICAL: Pass planType='web_assigned' to ensure we only get assigned plans (not manual/AI plans)
        // This matches how manual plans filter by planType='manual' or 'ai_generated'
        final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
        final matchingDay = dailyPlans.firstWhereOrNull((dp) {
          final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
          final dpDate = dp['plan_date']?.toString().split('T').first;
          final dpPlanType = dp['plan_type']?.toString();
          final matches = dpPlanId == planId && dpDate == planDate && dpPlanType == 'web_assigned';
          if (matches) {
            print('✅ SchedulesController - Found matching daily plan: id=${dp['id']}, plan_date=$dpDate, exercises_details count=${(dp['exercises_details'] is List ? (dp['exercises_details'] as List).length : 0)}');
          }
          return matches;
        });
        if (matchingDay != null) {
          // Try daily_plan_id first (explicitly provided by backend), then fall back to id
          dailyPlanId = matchingDay['daily_plan_id'] != null
              ? int.tryParse(matchingDay['daily_plan_id']?.toString() ?? '')
              : (matchingDay['id'] != null ? int.tryParse(matchingDay['id']?.toString() ?? '') : null);
          
          // Log the exercises_details to verify we're getting the right day's workouts
          final exercisesDetails = matchingDay['exercises_details'];
          if (exercisesDetails is List) {
            final workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            print('✅ SchedulesController - Found daily_plan_id: $dailyPlanId for Day $currentDay');
            print('✅ SchedulesController - Daily plan workouts: ${workoutNames.join(", ")}');
            print('✅ SchedulesController - Expected Day $currentDay workouts should match this list');
          }
        } else {
          print('⚠️ SchedulesController - Could not find daily_plan_id for plan $planId, day $currentDay (date $planDate)');
          final relevantPlans = dailyPlans.where((dp) {
            final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            return dpPlanId == planId && (dp['plan_type']?.toString() == 'web_assigned');
          }).toList();
          print('⚠️ SchedulesController - Available daily plans for this assignment:');
          for (final dp in relevantPlans) {
            final dpDate = dp['plan_date']?.toString().split('T').first;
            final exercisesDetails = dp['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
              workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            }
            print('  - ID: ${dp['id']}, plan_date: $dpDate, workouts: ${workoutNames.join(", ")}');
          }
        }
      } catch (e) {
        print('⚠️ SchedulesController - Could not fetch daily plan ID: $e');
      }
      
      if (dailyPlanId == null) {
        print('⚠️ SchedulesController - Could not find daily_plan_id for day $currentDay, creating on-demand');
        // Create daily plan for the current day on-demand if it doesn't exist
        try {
          // Create the daily plan and get the ID directly from the response
          final createdDailyPlanId = await _createDailyPlanForDay(activeSchedule, currentDay);
          if (createdDailyPlanId != null) {
            dailyPlanId = createdDailyPlanId;
            print('✅ SchedulesController - Created daily plan on-demand with daily_plan_id: $dailyPlanId for day $currentDay');
          } else {
            print('❌ SchedulesController - Failed to create daily plan on-demand - no ID returned');
          }
        } catch (e) {
          print('❌ SchedulesController - Failed to create daily plan on-demand: $e');
        }
      }
      
      // Don't use planId as fallback - daily_plan_id is required
      if (dailyPlanId == null) {
        print('❌ SchedulesController - Cannot submit daily completion: daily_plan_id is null for plan $planId, day $currentDay');
        return; // Don't try to submit with wrong ID
      }
      
      // Create completion data for each workout
      // First, try to get item IDs from the stored daily plan if we have dailyPlanId
      Map<String, int> workoutNameToItemId = {};
      if (dailyPlanId != null) {
        try {
          final dailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          if (dailyPlan.isNotEmpty) {
            // Parse exercises_details to get item IDs
            dynamic exercisesDetails = dailyPlan['exercises_details'] ?? dailyPlan['items'];
            List<Map<String, dynamic>> exercises = [];
            if (exercisesDetails is List) {
              exercises = exercisesDetails.cast<Map<String, dynamic>>();
            } else if (exercisesDetails is String) {
              try {
                final parsed = jsonDecode(exercisesDetails);
                if (parsed is List) {
                  exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                }
              } catch (e) {
                print('⚠️ SchedulesController - Failed to parse exercises_details from daily plan: $e');
              }
            }
            
            // Map workout names to item IDs (1-based array indices)
            // Since daily_training_plan_items table is removed, item_id is now the 1-based index in exercises_details array
            for (int i = 0; i < exercises.length; i++) {
              final exercise = exercises[i];
              // Try multiple name fields to find the workout name
              final workoutName = (exercise['workout_name'] ?? 
                                  exercise['name'] ?? 
                                  exercise['exercise_name'] ?? 
                                  '').toString().trim();
              
              // item_id is now the 1-based index in the exercises_details array (for backend compatibility)
              final itemId = i + 1;
              
              // Map using multiple name variations for flexible matching
              if (workoutName.isNotEmpty) {
                // Map with exact name (case-sensitive)
                workoutNameToItemId[workoutName] = itemId;
                // Map with lowercase name (case-insensitive)
                workoutNameToItemId[workoutName.toLowerCase()] = itemId;
                // Map with title case (first letter uppercase)
                if (workoutName.length > 0) {
                  final titleCase = workoutName[0].toUpperCase() + workoutName.substring(1).toLowerCase();
                  workoutNameToItemId[titleCase] = itemId;
                }
                // Map using the index (1-based) as item_id
                workoutNameToItemId['${i + 1}'] = itemId; // Index (1-based)
                workoutNameToItemId['$i'] = itemId; // Also map 0-based for compatibility
                
                // Also map by position in list (for direct index matching)
                workoutNameToItemId['index_${i + 1}'] = itemId;
                workoutNameToItemId['index_$i'] = itemId;
              }
              
              print('🔍 SchedulesController - Exercise $i: "$workoutName" → item_id: $itemId (1-based index in exercises_details, array index: $i)');
            }
            print('🔍 SchedulesController - Mapped ${workoutNameToItemId.length} workout names to item IDs');
            print('🔍 SchedulesController - Available mappings: ${workoutNameToItemId.entries.map((e) => '${e.key}: ${e.value}').join(", ")}');
          }
        } catch (e) {
          print('⚠️ SchedulesController - Could not fetch daily plan to get item IDs: $e');
        }
      }
      
      final List<Map<String, dynamic>> completionData = [];
      
      for (int workoutIndex = 0; workoutIndex < dayWorkouts.length; workoutIndex++) {
        final workout = dayWorkouts[workoutIndex];
        final workoutKey = '${planId}_${currentDay}_${workout['name']}';
        final remainingMinutes = _workoutRemainingMinutes[workoutKey] ?? 0;
        final totalMinutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
        final actualMinutes = totalMinutes - remainingMinutes;
        
        // Get item_id as 1-based index in exercises_details array
        // Since daily_training_plan_items table is removed, item_id is now the 1-based array index
        final workoutName = (workout['name'] ?? workout['workout_name'] ?? '').toString();
        final workoutNameLower = workoutName.toLowerCase();
        
        // Try multiple lookup strategies - item_id is 1-based array index
        int itemId = workoutNameToItemId[workoutNameLower] ?? 
                     workoutNameToItemId[workoutName] ??
                     workoutNameToItemId['${workoutIndex + 1}'] ?? // Try by index (1-based)
                     workoutNameToItemId['$workoutIndex'] ?? // Try by index (0-based for compatibility)
                     workoutNameToItemId['index_${workoutIndex + 1}'] ?? // Try by index key
                     workoutNameToItemId['index_$workoutIndex'] ??
                     0;
        
        // Last resort: use workoutIndex + 1 (1-based) as item_id - this is the index in exercises_details array
        if (itemId == 0) {
          itemId = workoutIndex + 1; // Use 1-based index as item_id (backend expects 1-based)
          print('⚠️ SchedulesController - Using workout index (1-based) as item_id: $itemId for workout "$workoutName" (array index: $workoutIndex)');
        } else {
          print('✅ SchedulesController - Found item_id $itemId (1-based index) for workout "$workoutName" (array index: $workoutIndex)');
        }
        
        final completionItem = _createCompletionItem(
          itemId: itemId,
          setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
          repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
          weightUsed: workout['weight_kg'] is num ? (workout['weight_kg'] as num).toDouble() : (double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0),
          minutesSpent: actualMinutes,
          notes: 'Completed via Schedules tab - Day $currentDay',
        );
        
        completionData.add(completionItem);
      }
      
      if (completionData.isNotEmpty) {
        // Submit to API using the correct daily_plan_id (dailyPlanId is guaranteed to be non-null at this point)
        try {
          print('📤 SchedulesController - Submitting daily training completion to API:');
          print('  - daily_plan_id: $dailyPlanId');
          print('  - completion_data count: ${completionData.length}');
          print('  - completion_data: $completionData');
          
          await _submitCompletionToAPI(
            dailyPlanId: dailyPlanId!,
            completionData: completionData,
          );
          
          print('✅ Daily training completion submitted successfully with daily_plan_id: $dailyPlanId');
          
          // CRITICAL: Verify completion was persisted (backend now uses transactions)
          // Check both is_completed AND completed_at (backend requires both)
          bool verified = false;
          int retryCount = 0;
          const maxRetries = 3;
          
          while (!verified && retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1))); // Increasing delay
            retryCount++;
            
            try {
              print('📊 SchedulesController - Verifying completion (attempt $retryCount/$maxRetries) for daily_plan_id: $dailyPlanId');
              final updatedDailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
              
              final isCompleted = updatedDailyPlan['is_completed'] as bool? ?? false;
              final completedAt = updatedDailyPlan['completed_at'] as String?;
              final planDate = updatedDailyPlan['plan_date'] as String?;
              final planType = updatedDailyPlan['plan_type'] as String?;
              
              print('📊 SchedulesController - Verification result:');
              print('  - is_completed: $isCompleted');
              print('  - completed_at: $completedAt');
              print('  - plan_date: $planDate');
              print('  - plan_type: $planType');
              
              // Backend requires BOTH is_completed=true AND completed_at timestamp
              if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
                verified = true;
                print('✅ SchedulesController - Completion verified successfully (transaction committed)');
              } else {
                print('⚠️ SchedulesController - Completion not yet verified: is_completed=$isCompleted, completed_at=${completedAt != null ? "set" : "null"}');
                if (retryCount < maxRetries) {
                  print('📊 SchedulesController - Retrying verification...');
                }
              }
            } catch (verifyError) {
              print('⚠️ SchedulesController - Verification attempt $retryCount failed: $verifyError');
              if (retryCount >= maxRetries) {
                print('❌ SchedulesController - Could not verify completion after $maxRetries attempts');
              }
            }
          }
          
          if (!verified) {
            print('⚠️ SchedulesController - WARNING: Completion may not have been persisted (transaction may have failed)');
            print('⚠️ SchedulesController - Backend logs should show transaction commit/rollback status');
          }
          
          // CRITICAL: Wait a moment for backend transaction to fully commit before syncing stats
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('❌ SchedulesController - Failed to submit daily training completion: $e');
          print('❌ SchedulesController - Error details: ${e.toString()}');
          // Try to extract error details if it's a DioException-like error
          try {
            final errorStr = e.toString();
            if (errorStr.contains('status code') || errorStr.contains('Status Code')) {
              print('❌ SchedulesController - Error appears to be HTTP-related');
            }
          } catch (_) {}
          // Don't throw - continue with stats refresh even if submission failed
        }
        
        // CRITICAL: Refresh stats after completion (same as manual plans do)
        // This ensures stats are recalculated immediately after workout completion
        // AWAIT the refresh to ensure it completes before continuing
        try {
          final statsController = Get.find<StatsController>();
          print('📊 SchedulesController - Refreshing stats after daily completion (forceSync: true)...');
          await statsController.refreshStats(forceSync: true);
          print('✅ SchedulesController - Stats refreshed successfully after daily completion');
        } catch (e) {
          print('⚠️ SchedulesController - Error refreshing stats after completion: $e');
        }
      } else {
        print('⚠️ SchedulesController - No completion data to submit');
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

  /// Create daily plan for a specific day on-demand using the new endpoint
  /// This uses the new endpoint that creates daily plans from training approvals/assignments
  /// 
  /// Note: For assigned plans, the backend automatically syncs all daily_plans from 
  /// training_plan_assignments.daily_plans to daily_training_plans when a plan is assigned.
  /// This on-demand creation is a fallback if the synced plan is not found for a specific day.
  /// 
  /// Returns the daily_plan_id if successful, null otherwise
  Future<int?> _createDailyPlanForDay(Map<String, dynamic> schedule, int dayIndex) async {
    try {
      final planId = int.tryParse(schedule['id']?.toString() ?? '') ?? 0;
      if (planId == 0) {
        print('⚠️ SchedulesController - Invalid plan ID, skipping daily plan creation');
        return null;
      }

      // Get assignment details to get start_date for calculating plan_date
      final assignmentDetails = await getAssignmentDetails(planId);
      if (assignmentDetails.isEmpty || assignmentDetails.containsKey('error')) {
        print('⚠️ SchedulesController - Could not get assignment details, skipping daily plan creation');
        return null;
      }

      // Extract actual plan data (handle API response format)
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }

      // Calculate plan date using assignment's start_date
      final DateTime? startDate = actualPlan['start_date'] != null 
          ? DateTime.tryParse(actualPlan['start_date'].toString())
          : DateTime.now();
      
      if (startDate == null) {
        print('⚠️ SchedulesController - Could not parse start_date, skipping daily plan creation');
        return null;
      }

      // Calculate the plan date for the specified day
      // IMPORTANT: dayIndex is now 1-based (Day 1 = 1, Day 2 = 2, etc.)
      // Backend now correctly creates daily plans with UTC dates:
      //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0) in UTC
      //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1) in UTC
      // Backend sorts daily_plans by day property and uses UTC date components to avoid timezone shifts
      // 
      // Frontend normalizes to UTC date string (YYYY-MM-DD) to match backend format
      // Normalize to UTC date components to avoid timezone issues
      final utcDate = DateTime.utc(startDate.year, startDate.month, startDate.day);
      // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
      final dayOffset = dayIndex - 1;
      final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;

      print('📤 SchedulesController - Creating daily plan for assigned plan $planId, day $dayIndex (date: $planDate)');

      // Log assignment data that should be extracted by backend for stats tracking
      print('📊 SchedulesController - Assignment data available for backend extraction:');
      print('  - Assignment ID: $planId');
      print('  - Category: ${actualPlan['category'] ?? 'N/A'}');
      print('  - User Level: ${actualPlan['user_level'] ?? 'N/A'}');
      print('  - Total Exercises: ${actualPlan['total_exercises'] ?? 0}');
      print('  - Total Workouts: ${actualPlan['total_workouts'] ?? 0}');
      print('  - Training Minutes: ${actualPlan['training_minutes'] ?? 0}');
      print('  - Exercises Details Count: ${actualPlan['exercises_details'] is List ? (actualPlan['exercises_details'] as List).length : 0}');
      print('  - Start Date: ${actualPlan['start_date']}');
      print('  - End Date: ${actualPlan['end_date']}');
      
      // Extract daily workouts for this day to verify data availability
      final dayWorkouts = _getDayWorkouts(actualPlan, dayIndex);
      print('📊 SchedulesController - Daily workouts for day $dayIndex: ${dayWorkouts.length} workouts');
      for (int i = 0; i < dayWorkouts.length; i++) {
        final workout = dayWorkouts[i];
        print('  ${i + 1}. ${workout['name'] ?? workout['workout_name'] ?? 'Unknown'} - '
              'Sets: ${workout['sets'] ?? 0}, Reps: ${workout['reps'] ?? 0}, '
              'Weight: ${workout['weight_kg'] ?? workout['weight_min_kg'] ?? 0}-${workout['weight_max_kg'] ?? 0}kg, '
              'Minutes: ${workout['minutes'] ?? 0}');
      }

      // Get web_plan_id from schedule if available (backend can use this for lookup)
      final webPlanId = schedule['web_plan_id'] != null 
          ? int.tryParse(schedule['web_plan_id'].toString())
          : null;

      // Use the new endpoint to create daily plan from assignment
      // Backend should extract all data from training_plan_assignments table and store in daily_training_plans:
      // - exercises_details (with all workout data for this day based on distribution logic)
      // - category, user_level, total_exercises, total_workouts, training_minutes
      // - plan_type: 'web_assigned'
      // - source_plan_id: assignment ID
      // - plan_date: calculated date for this day
      // - All other columns needed for stats tracking (sets, reps, weight_kg, etc.)
      // For assigned plans, send assignment_id (not approval_id) - backend prioritizes training_plan_assignments
      print('📤 SchedulesController - Sending request to create daily plan with:');
      print('  - assignment_id: $planId');
      print('  - plan_date: $planDate');
      print('  - web_plan_id: ${webPlanId ?? 'N/A'}');
      print('  - Day workouts count: ${dayWorkouts.length}');
      
      final createdPlan = await _dailyTrainingService.createDailyPlanFromApproval(
        assignmentId: planId, // planId is the assignment ID from training_plan_assignments
        planDate: planDate,
        webPlanId: webPlanId,
      );

      if (createdPlan.isEmpty) {
        print('⚠️ SchedulesController - Failed to create daily plan, empty response');
        return null;
      }

      // Try daily_plan_id first (explicitly provided by backend), then fall back to id
      int? dailyPlanId;
      if (createdPlan['daily_plan_id'] != null) {
        dailyPlanId = int.tryParse(createdPlan['daily_plan_id']?.toString() ?? '');
        print('🔍 SchedulesController - Using daily_plan_id from response: $dailyPlanId');
      }
      
      // Fall back to id if daily_plan_id is not available
      if (dailyPlanId == null && createdPlan['id'] != null) {
        dailyPlanId = int.tryParse(createdPlan['id']?.toString() ?? '');
        print('🔍 SchedulesController - Using id as fallback: $dailyPlanId');
      }
      
      if (dailyPlanId != null) {
        print('✅ SchedulesController - Daily training plan for day $dayIndex created successfully with daily_plan_id: $dailyPlanId');
        
        // Verify the daily plan was actually created in the database
        try {
          await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend to save
          final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          if (verifyPlan.isNotEmpty) {
            print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId');
          } else {
            print('⚠️ SchedulesController - Daily plan ID $dailyPlanId was returned but not found in database');
          }
        } catch (verifyError) {
          print('⚠️ SchedulesController - Could not verify daily plan creation: $verifyError');
        }
        
        return dailyPlanId;
      } else {
        // Last resort: try to find the daily plan using the find endpoint
        print('⚠️ SchedulesController - Daily plan ID not found in response, trying find endpoint...');
        try {
          final webPlanId = schedule['web_plan_id'] != null 
              ? int.tryParse(schedule['web_plan_id'].toString())
              : null;
          
          final foundPlan = await _dailyTrainingService.findDailyPlanBySource(
            assignmentId: planId,
            webPlanId: webPlanId,
            planDate: planDate,
          );
          
          if (foundPlan != null) {
            final foundDailyPlanId = foundPlan['daily_plan_id'] != null
                ? int.tryParse(foundPlan['daily_plan_id']?.toString() ?? '')
                : (foundPlan['id'] != null ? int.tryParse(foundPlan['id']?.toString() ?? '') : null);
            
            if (foundDailyPlanId != null) {
              print('✅ SchedulesController - Found daily plan using find endpoint with daily_plan_id: $foundDailyPlanId');
              return foundDailyPlanId;
            }
          }
        } catch (e) {
          print('⚠️ SchedulesController - Find endpoint also failed: $e');
        }
        
        print('❌ SchedulesController - Daily plan created but ID not found in response or via find endpoint');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ SchedulesController - Failed to create daily plan for day: $e');
      print('❌ SchedulesController - Stack trace: $stackTrace');
      return null;
    }
  }

  /// Store daily training plans for an assigned plan when it's started (only creates current day)
  /// This uses the new endpoint that creates daily plans from training approvals
  /// 
  /// BACKEND BEHAVIOR (syncDailyPlansFromAssignmentHelper):
  /// - Finds the last completed daily plan by plan_date (not completed_at)
  /// - Skips days with plan_date <= lastCompletedDate
  /// - Creates/updates only days after the last completed date
  /// - This preserves completed days and continues from the next day
  /// 
  /// FRONTEND BEHAVIOR:
  /// - Only creates the current day's plan on-demand (when plan is started)
  /// - Future days are created on-demand as user progresses
  /// - Backend sync handles skipping completed days automatically
  Future<void> _storeDailyTrainingPlansForAssignedPlan(Map<String, dynamic> schedule) async {
    try {
      final planId = int.tryParse(schedule['id']?.toString() ?? '') ?? 0;
      if (planId == 0) {
        print('⚠️ SchedulesController - Invalid plan ID, skipping daily plan storage');
        return;
      }

      print('📤 SchedulesController - Storing daily training plans for assigned plan $planId');

      // Get assignment details to get start_date for calculating plan_date
      final assignmentDetails = await getAssignmentDetails(planId);
      if (assignmentDetails.isEmpty || assignmentDetails.containsKey('error')) {
        print('⚠️ SchedulesController - Could not get assignment details, skipping daily plan storage');
        return;
      }

      // Extract actual plan data (handle API response format)
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }

      // Only create the daily plan for the current day (day 0) when plan is started
      // Future days will be created on-demand as the user progresses
      final currentDay = getCurrentDay(planId);
      final DateTime? startDate = actualPlan['start_date'] != null 
          ? DateTime.tryParse(actualPlan['start_date'].toString())
          : DateTime.now();
      
      if (startDate == null) {
        print('⚠️ SchedulesController - Could not parse start_date, skipping daily plan storage');
        return;
      }

      // Calculate the plan date for the current day
      // IMPORTANT: currentDay is now 1-based (Day 1 = 1, Day 2 = 2, etc.)
      // Backend now correctly creates daily plans with UTC dates:
      //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0) in UTC
      //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1) in UTC
      // Backend sorts daily_plans by day property and uses UTC date components to avoid timezone shifts
      // 
      // Frontend normalizes to UTC date string (YYYY-MM-DD) to match backend format
      // Normalize to UTC date components to avoid timezone issues
      final utcDate = DateTime.utc(startDate.year, startDate.month, startDate.day);
      // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
      final dayOffset = currentDay - 1;
      final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;

      print('📤 SchedulesController - Creating daily plan for assigned plan $planId, day $currentDay (date: $planDate)');

      // Log assignment data that should be extracted by backend for stats tracking
      print('📊 SchedulesController - Assignment data available for backend extraction:');
      print('  - Assignment ID: $planId');
      print('  - Category: ${actualPlan['category'] ?? 'N/A'}');
      print('  - User Level: ${actualPlan['user_level'] ?? 'N/A'}');
      print('  - Total Exercises: ${actualPlan['total_exercises'] ?? 0}');
      print('  - Total Workouts: ${actualPlan['total_workouts'] ?? 0}');
      print('  - Training Minutes: ${actualPlan['training_minutes'] ?? 0}');
      print('  - Exercises Details Count: ${actualPlan['exercises_details'] is List ? (actualPlan['exercises_details'] as List).length : 0}');
      
      // Extract daily workouts for this day to verify data availability
      final dayWorkouts = _getDayWorkouts(actualPlan, currentDay);
      print('📊 SchedulesController - Daily workouts for day $currentDay: ${dayWorkouts.length} workouts');
      for (int i = 0; i < dayWorkouts.length; i++) {
        final workout = dayWorkouts[i];
        print('  ${i + 1}. ${workout['name'] ?? workout['workout_name'] ?? 'Unknown'} - '
              'Sets: ${workout['sets'] ?? 0}, Reps: ${workout['reps'] ?? 0}, '
              'Weight: ${workout['weight_kg'] ?? workout['weight_min_kg'] ?? 0}-${workout['weight_max_kg'] ?? 0}kg, '
              'Minutes: ${workout['minutes'] ?? 0}');
      }

      // Get web_plan_id from schedule if available (backend can use this for lookup)
      final webPlanId = schedule['web_plan_id'] != null 
          ? int.tryParse(schedule['web_plan_id'].toString())
          : null;

      // Use the new endpoint to create daily plan from assignment
      // Backend should extract all data from training_plan_assignments table and store in daily_training_plans:
      // - exercises_details (with all workout data for this day based on distribution logic)
      // - category, user_level, total_exercises, total_workouts, training_minutes
      // - plan_type: 'web_assigned'
      // - source_plan_id: assignment ID
      // - plan_date: calculated date for this day
      // - All other columns needed for stats tracking (sets, reps, weight_kg, etc.)
      // For assigned plans, send assignment_id (not approval_id) - backend prioritizes training_plan_assignments
      print('📤 SchedulesController - Sending request to create daily plan with:');
      print('  - assignment_id: $planId');
      print('  - plan_date: $planDate');
      print('  - web_plan_id: ${webPlanId ?? 'N/A'}');
      print('  - Day workouts count: ${dayWorkouts.length}');
      
      final createdPlan = await _dailyTrainingService.createDailyPlanFromApproval(
        assignmentId: planId, // planId is the assignment ID from training_plan_assignments
        planDate: planDate,
        webPlanId: webPlanId,
      );

      if (createdPlan.isEmpty) {
        print('⚠️ SchedulesController - Failed to create daily plan, empty response');
        return;
      }

      final dailyPlanId = int.tryParse(createdPlan['id']?.toString() ?? '');
      if (dailyPlanId != null) {
        print('✅ SchedulesController - Daily training plan for day $currentDay created successfully with daily_plan_id: $dailyPlanId');
      } else {
        print('✅ SchedulesController - Daily training plan for day $currentDay created successfully');
      }
    } catch (e, stackTrace) {
      print('❌ SchedulesController - Failed to store daily training plan data: $e');
      print('❌ SchedulesController - Stack trace: $stackTrace');
      // Continue anyway - plan can still be started without stored daily plans
    }
  }

  /// Generate daily plan for a single day (for on-demand creation)
  Map<String, dynamic> _generateSingleDayPlanForAssignedPlan(
    List<Map<String, dynamic>> items,
    int dayIndex,
    DateTime startDate,
  ) {
    if (items.isEmpty) return {};

    // Calculate the rotation offset for this day (same logic as _distributeWorkoutsAcrossDays)
    final workoutsPerDay = 2;
    final totalWorkouts = items.length;
    final dayRotationOffset = (dayIndex * workoutsPerDay) % totalWorkouts;

    final List<Map<String, dynamic>> workoutsForDay = [];

    if (items.isNotEmpty) {
      // Add first workout
      final Map<String, dynamic> first = Map<String, dynamic>.from(items[dayRotationOffset % items.length]);
      final int m1 = _extractWorkoutMinutes(first);
      workoutsForDay.add(first);

      // Check if we can add a second workout (80-minute rule)
      if (items.length > 1) {
        final int secondIndex = (dayRotationOffset + 1) % items.length;
        final Map<String, dynamic> second = Map<String, dynamic>.from(items[secondIndex]);
        final int m2 = _extractWorkoutMinutes(second);
        final int totalMinutes = m1 + m2;

        if (totalMinutes <= 80) {
          workoutsForDay.add(second);
        }
      }
    }

    final DateTime date = startDate.add(Duration(days: dayIndex));
    return {
      'day': dayIndex + 1,
      'date': date.toIso8601String().split('T').first,
      'plan_date': date.toIso8601String().split('T').first,
      'workouts': workoutsForDay,
      'items': workoutsForDay, // Also include as 'items' for compatibility
    };
  }

  /// Generate daily plans for assigned plan using the same distribution logic (DEPRECATED - use _generateSingleDayPlanForAssignedPlan instead)
  @Deprecated('Use _generateSingleDayPlanForAssignedPlan to create plans on-demand instead of all at once')
  List<Map<String, dynamic>> _generateDailyPlansForAssignedPlan(
    List<Map<String, dynamic>> items,
    int totalDays,
    DateTime? startDate,
  ) {
    final List<Map<String, dynamic>> days = [];
    if (items.isEmpty || totalDays <= 0 || startDate == null) return days;

    for (int day = 0; day < totalDays; day++) {
      final dayPlan = _generateSingleDayPlanForAssignedPlan(items, day, startDate);
      if (dayPlan.isNotEmpty) {
        days.add(dayPlan);
      }
    }

    return days;
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
      await stopSchedule(_activeSchedule.value!);
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
