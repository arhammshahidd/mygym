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
  
  // Track active workout timers to prevent memory leaks
  final Map<String, Timer> _activeTimers = {};
  
  // Guard to prevent multiple simultaneous day completion submissions
  bool _isSubmittingCompletion = false;
  final Map<String, bool> _submissionInProgress = {}; // Track submissions per planId+day

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
    // Cancel all active timers to prevent memory leaks
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    
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
          // CRITICAL: Also validate that assignment belongs to current user
          final filteredAssignments = assignmentsRes.where((assignment) {
            // CRITICAL: First check if assignment belongs to current user
            final assignmentUserId = assignment['user_id'] as int?;
            if (assignmentUserId != null && assignmentUserId != userId) {
              print('❌ Schedules - REJECTED: Assignment ${assignment['id']} belongs to user $assignmentUserId, but current user is $userId');
              return false;
            }
            
            // Check if this is a truly assigned plan
            final planType = assignment['plan_type']?.toString().toLowerCase();
            final assignmentId = assignment['assignment_id'];
            final assignedAt = assignment['assigned_at'];
            final assignedBy = assignment['assigned_by'];
            final trainerId = assignment['trainer_id'];
            final webPlanId = assignment['web_plan_id'];
            final status = assignment['status']?.toString().toUpperCase();
            
            // Enhanced check for assigned plans based on database structure
            // CRITICAL: web_assigned plans belong in Schedules tab, not Plans tab
            final isAssigned = assignmentId != null || 
                              assignedAt != null ||
                              assignedBy != null ||
                              trainerId != null || // Has trainer_id (assigned by trainer)
                              webPlanId != null || // Has web_plan_id (from web portal)
                              planType == 'assigned' ||
                              planType == 'web_assigned' ||
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
            print('🔍   - user_id: $assignmentUserId (current user: $userId)');
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
          // SECURITY: Don't use fallback with hardcoded user ID - this could expose another user's data
          // Clear assignments to show empty state instead
          assignments.clear();
          print('⚠️ Schedules - Assignments cleared due to fetch error (no fallback to prevent data leakage)');
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
  
  /// Submit completion data to API (mobile completion endpoint)
  Future<void> _submitCompletionToAPI({
    required int dailyPlanId,
    required String planType,
    bool isCompleted = true,
    String? notes,
    List<Map<String, dynamic>>? completionData, // kept for logging/reference
  }) async {
    try {
      print('🔍 SchedulesController - _submitCompletionToAPI called:');
      print('  - daily_plan_id: $dailyPlanId');
      print('  - plan_type: $planType');
      print('  - is_completed: $isCompleted');
      if (notes != null) print('  - completion_notes: $notes');
      if (completionData != null) {
        print('  - completion_data count: ${completionData.length}');
      }
      print('🔍 Submitting completion to API via DailyTrainingService');
      print('🔍 API Endpoint: POST /api/dailyTraining/mobile/complete');
      print('🔍 Request payload: {daily_plan_id: $dailyPlanId, completion_data: ${completionData?.length ?? 0} items}');
      
      await _dailyTrainingService.submitDailyTrainingCompletion(
        planId: dailyPlanId,
        completionData: completionData ?? <Map<String, dynamic>>[],
      );
      
      print('✅ SchedulesController - API call completed successfully');
      print('✅ SchedulesController - Response received from /api/dailyTraining/mobile/complete');
      print('✅ SchedulesController - Completion submitted successfully');
    } catch (e) {
      print('❌ SchedulesController - Failed to submit completion to API: $e');
      print('❌ SchedulesController - Error type: ${e.runtimeType}');
      // Check if it's a DioException-like error (has response property)
      try {
        final errorStr = e.toString();
        if (errorStr.contains('DioException') || errorStr.contains('status code') || errorStr.contains('Status Code')) {
          print('❌ SchedulesController - HTTP error detected');
          // Try to extract status code and response from error string
          if (errorStr.contains('status code')) {
            print('❌ SchedulesController - Check error message above for status code and response details');
          }
        }
      } catch (_) {}
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

  /// Get the current day for an assigned plan based on backend completion data.
  ///
  /// NEW primary strategy (aligned with backend `getDailyPlans` behavior):
  /// - Call `/api/dailyTraining/mobile/plans` via `getDailyPlans(planType: 'web_assigned')`.
  /// - Filter to this assignment (`source_assignment_id` / `source_plan_id` = scheduleId).
  /// - Backend already:
  ///   - Preserves `is_completed` / `completed_at` for historical rows.
  ///   - Starts the list from the **first incomplete day**.
  /// - We map using explicit `day_number` (or `day`) coming from backend plans.
  ///
  /// Fallback strategy (if API/assignment data is missing):
  /// - Use `_getLastCompletedDayFromDatabase()` as the single source of truth for
  ///   "last completed day" and compute `completedDay + 1`, clamped to total days.
  ///
  /// This ensures:
  /// - We never "go backwards" to a completed day when restarting a plan.
  /// - We trust the backend's "first incomplete day" semantics whenever possible.
  Future<int?> _getCurrentDayFromBackendPlans(int scheduleId) async {
    try {
      // 0) Try using backend `getDailyPlans` (which already starts from first incomplete day).
      try {
        print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): calling getDailyPlans(planType: web_assigned) for schedule $scheduleId');
        final rawPlans = await _dailyTrainingService.getDailyPlans(planType: 'web_assigned');
        print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): getDailyPlans returned ${rawPlans.length} plans');

        // Filter to this assignment and exclude stats records
        final assignmentPlans = rawPlans.where((p) {
          final sourceAssignmentId = p['source_assignment_id'] as int?;
          final sourcePlanId = p['source_plan_id'] as int?;
          final isStatsRecord = p['is_stats_record'] as bool? ?? false;
          final idMatches = (sourceAssignmentId == scheduleId || sourcePlanId == scheduleId);
          if (idMatches) {
            print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): candidate plan for schedule $scheduleId → id=${p['id']}, day_number=${p['day_number'] ?? p['day']}, is_completed=${p['is_completed']}, is_stats_record=$isStatsRecord');
          }
          return idMatches && !isStatsRecord; // Exclude stats records
        }).toList();

        // Helper to extract day number from plan
        int? _dayNum(Map p) {
          return int.tryParse(p['day_number']?.toString() ?? p['day']?.toString() ?? '');
        }

        // CRITICAL: Filter to only incomplete plans and sort by day_number (fallback to id order)
        final incompletePlans = assignmentPlans.where((p) => !(p['is_completed'] as bool? ?? false)).toList();
        incompletePlans.sort((a, b) {
          final aDay = _dayNum(a) ?? 99999;
          final bDay = _dayNum(b) ?? 99999;
          if (aDay == bDay) {
            return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
          }
          return aDay.compareTo(bDay);
        });

        if (incompletePlans.isNotEmpty) {
          final currentPlan = incompletePlans.first;
          final dayNumber = _dayNum(currentPlan) ?? 1;
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): first incomplete plan for schedule $scheduleId has day=$dayNumber, is_completed=${currentPlan['is_completed']}');
          return dayNumber;
        } else {
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): no incomplete plans found for schedule $scheduleId (all plans may be completed), falling back to DB logic');
        }
      } catch (e) {
        print('⚠️ SchedulesController - _getCurrentDayFromBackendPlans(): getDailyPlans path failed: $e');
      }

      // 1) Fallback: Ask database/stats logic for the last completed day.
      final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
      print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): fallback last completed day from DB = $completedDay');

      // 2) If there is no completed day, start from Day 1.
      if (completedDay == null || completedDay <= 0) {
        print('📅 SchedulesController - Fallback: no completed days found, starting at Day 1');
        return 1;
      }

      // 3) Determine how many days exist in this assignment from assignment.daily_plans
      int totalDays = 0;
      try {
        final assignmentDetails = await getAssignmentDetails(scheduleId);
        Map<String, dynamic> actualPlan = assignmentDetails;
        if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
          actualPlan = assignmentDetails['data'] ?? {};
        }

        final dailyPlansRaw = actualPlan['daily_plans'];
        List<Map<String, dynamic>> dailyPlans = [];
        if (dailyPlansRaw != null) {
          if (dailyPlansRaw is String) {
            try {
              final parsed = jsonDecode(dailyPlansRaw) as List?;
              if (parsed != null) {
                dailyPlans = parsed.cast<Map<String, dynamic>>();
              }
            } catch (e) {
              print('⚠️ SchedulesController - _getCurrentDayFromBackendPlans (fallback): error parsing daily_plans JSON: $e');
            }
          } else if (dailyPlansRaw is List) {
            dailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
          }
        }

        // Prefer explicit `day` field to determine total days; fall back to list length.
        int maxDayField = 0;
        for (final dp in dailyPlans) {
          final d = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
          if (d > maxDayField) maxDayField = d;
        }
        totalDays = maxDayField > 0 ? maxDayField : dailyPlans.length;
        print('📅 SchedulesController - _getCurrentDayFromBackendPlans (fallback): totalDays inferred as $totalDays');
      } catch (e) {
        print('⚠️ SchedulesController - _getCurrentDayFromBackendPlans (fallback): error while inferring totalDays: $e');
      }

      // 4) Compute the first incomplete day, clamped to [1, totalDays] if totalDays is known.
      int candidate = completedDay + 1;
      if (totalDays > 0 && candidate > totalDays) {
        // All days completed – stay on last day
        candidate = totalDays;
        print('📅 SchedulesController - _getCurrentDayFromBackendPlans (fallback): all $totalDays days completed, staying on Day $candidate');
      } else {
        print('📅 SchedulesController - _getCurrentDayFromBackendPlans (fallback): first incomplete day candidate = Day $candidate (completedDay=$completedDay, totalDays=$totalDays)');
      }

      return candidate;
    } catch (e) {
      print('⚠️ SchedulesController - Failed to get current day from backend daily plans: $e');
      return null;
    }
  }

  void startSchedule(Map<String, dynamic> schedule) async {
    final int? scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) return;
    
    // Check if there's already an active plan (from any tab)
    final existingActivePlan = await _getAnyActivePlan();
    if (existingActivePlan != null) {
      final currentPlanId = int.tryParse(existingActivePlan['id']?.toString() ?? '');
      
      // If trying to start the same plan, just return (matches manual plan behavior)
      // The plan is already active and the day is already set correctly
      if (currentPlanId == scheduleId) {
        print('ℹ️ SchedulesController - Schedule $scheduleId is already active, no action needed');
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
    // This matches the exact pattern used in manual plans (plans_controller.dart)
    int? cachedDay;
    try {
      print('📅 SchedulesController - Checking database for completed days (database is source of truth)...');
      final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
      if (completedDay != null) {
        // completedDay is 1-based (from daily_plans), _currentDay is 1-based for assigned plans
        // If completedDay = 2 (Day 2 completed), we should resume at Day 3
        final nextDay = completedDay + 1; // completedDay is 1-based, add 1 to get next day (also 1-based)
        _currentDay[scheduleId.toString()] = nextDay;
        _persistCurrentDayToCache(scheduleId, nextDay);
        print('📅 SchedulesController - ✅ Found completed day $completedDay (1-based) in database, resuming at day $nextDay (1-based, Day $nextDay)');
        cachedDay = nextDay;
      } else {
        // If no completed days in database, check cache as fallback
        await _loadCurrentDayFromCache(scheduleId);
        cachedDay = _currentDay[scheduleId.toString()];
        if (cachedDay != null) {
          print('📅 SchedulesController - Using cached day $cachedDay as fallback');
        }
      }
    } catch (e) {
      print('⚠️ SchedulesController - Error checking database for completed days: $e');
      // If database check fails, fall back to cache
      await _loadCurrentDayFromCache(scheduleId);
      cachedDay = _currentDay[scheduleId.toString()];
      if (cachedDay != null) {
        print('📅 SchedulesController - Using cached day $cachedDay after database error');
      }
    }
    
    if (cachedDay == null) {
      // First time starting this plan, start at day 1 (1-based for assigned plans)
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
    
    // Force UI refresh (matches manual plan behavior)
    update();
    
    // Refresh stats when plan is started to show current values (matches manual plan behavior)
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
    
    // Cancel all active timers for this schedule
    final schedulePrefix = '${scheduleId}_';
    final timersToCancel = _activeTimers.keys.where((key) => key.startsWith(schedulePrefix)).toList();
    for (final key in timersToCancel) {
      _activeTimers[key]?.cancel();
      _activeTimers.remove(key);
    }
    
    _startedSchedules[scheduleId] = false;
    if (_activeSchedule.value != null && (_activeSchedule.value!['id']?.toString() ?? '') == scheduleId.toString()) {
      _activeSchedule.value = null;
    }

    // Clear cached day/state for this schedule to avoid stale submissions
    _currentDay.remove(scheduleId.toString());
    await _clearCurrentDayFromCache(scheduleId);
    _completedWorkouts.removeWhere((key, _) => key.startsWith('${scheduleId}_'));
    _workoutStarted.removeWhere((key, _) => key.startsWith('${scheduleId}_'));
    _workoutCompleted.removeWhere((key, _) => key.startsWith('${scheduleId}_'));
    _workoutRemainingMinutes.removeWhere((key, _) => key.startsWith('${scheduleId}_'));
    
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
    
    // Force UI refresh (matches manual plan behavior)
    update();
    print('🛑 SchedulesController - Schedule $scheduleId stopped, UI updated');
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
    print('🚀 SchedulesController - startWorkout() CALLED');
    print('🚀 SchedulesController - workoutKey: $workoutKey');
    print('🚀 SchedulesController - totalMinutes: $totalMinutes');
    
    _workoutStarted[workoutKey] = true;
    _workoutRemainingMinutes[workoutKey] = totalMinutes;
    _workoutCompleted[workoutKey] = false;
    
    print('✅ SchedulesController - Workout started: $workoutKey (${totalMinutes} minutes)');
    print('✅ SchedulesController - Starting timer for workout...');
    
    // Start timer
    _startWorkoutTimer(workoutKey);
    
    print('✅ SchedulesController - Timer started for workout: $workoutKey');
  }

  void _startWorkoutTimer(String workoutKey) {
    print('⏱️ SchedulesController - _startWorkoutTimer() called for: $workoutKey');
    
    // Cancel existing timer for this workout if any
    _activeTimers[workoutKey]?.cancel();
    
    print('⏱️ SchedulesController - Creating Timer.periodic (1 minute interval) for: $workoutKey');
    
    final timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      print('⏱️ SchedulesController - Timer tick for workout: $workoutKey');
      if (!(_workoutStarted[workoutKey] ?? false)) {
        timer.cancel();
        _activeTimers.remove(workoutKey);
        return;
      }
      
      final remaining = _workoutRemainingMinutes[workoutKey] ?? 0;
      if (remaining <= 1) {
        // Workout completed
        print('✅ SchedulesController - Workout timer completed for key: $workoutKey');
        print('✅ SchedulesController - Marking workout as completed: $workoutKey');
        _workoutCompleted[workoutKey] = true;
        _workoutStarted[workoutKey] = false;
        _workoutRemainingMinutes[workoutKey] = 0;
        timer.cancel();
        _activeTimers.remove(workoutKey);
        
        print('✅ SchedulesController - Workout marked as completed. Current completed workouts: ${_workoutCompleted.keys.where((k) => _workoutCompleted[k] == true).toList()}');

        // Submit single workout completion immediately to stats
        _submitSingleWorkoutCompletion(workoutKey);
        
        // Check if all workouts for the day are completed
        print('🔍 SchedulesController - Calling _checkDayCompletion() after workout completion...');
        _checkDayCompletion();
      } else {
        _workoutRemainingMinutes[workoutKey] = remaining - 1;
      }
    });
    
    // Store timer for cleanup
    _activeTimers[workoutKey] = timer;
  }

  Future<void> _checkDayCompletion() async {
    print('🚀 SchedulesController - _checkDayCompletion() CALLED');
    final activeSchedule = _activeSchedule.value;
    if (activeSchedule == null) {
      print('⚠️ SchedulesController - No active schedule - cannot check day completion');
      return;
    }
    
    final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
    final currentDay = getCurrentDay(planId);
    
    print('🚀 SchedulesController - Checking completion for plan $planId, day $currentDay');
    
    // CRITICAL: Create a unique key for this submission to prevent duplicate submissions
    final submissionKey = '${planId}_${currentDay}';
    
    // Guard: Prevent multiple simultaneous submissions for the same day
    if (_isSubmittingCompletion || _submissionInProgress[submissionKey] == true) {
      print('⚠️ SchedulesController - Submission already in progress for plan $planId, day $currentDay - skipping duplicate check');
      print('⚠️ SchedulesController - _isSubmittingCompletion: $_isSubmittingCompletion');
      print('⚠️ SchedulesController - _submissionInProgress[$submissionKey]: ${_submissionInProgress[submissionKey]}');
      return;
    }
    
    // CRITICAL: Check if this day is already completed in the database BEFORE checking workout completion
    // This prevents submitting Day 2 when only Day 1 should be submitted
    try {
      final completedDay = await _getLastCompletedDayFromDatabase(planId);
      if (completedDay != null && completedDay >= currentDay) {
        print('⚠️ SchedulesController - Day $currentDay is already completed in database (last completed: Day $completedDay)');
        print('⚠️ SchedulesController - Skipping completion check to prevent duplicate submission');
        print('⚠️ SchedulesController - This prevents submitting Day 2 when only Day 1 should be submitted');
        return; // Exit early - day is already completed
      }
    } catch (e) {
      print('⚠️ SchedulesController - Error checking database for completed day: $e');
      // Continue with completion check if database check fails
    }
    
    // Get all workouts for current day - CAPTURE THIS BEFORE ANY STATE CHANGES
    final dayWorkouts = _getDayWorkouts(activeSchedule, currentDay);
    final workoutKeys = dayWorkouts.map((workout) => '${planId}_${currentDay}_${workout['name']}').toList();
    
    print('🔍 SchedulesController - Checking day completion for plan $planId, day $currentDay');
    print('🔍 SchedulesController - Day workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
    print('🔍 SchedulesController - Workout keys: $workoutKeys');
    print('🔍 SchedulesController - Completed workouts: ${_workoutCompleted.keys.toList()}');
    
    // Check completion status for each workout
    print('🔍 SchedulesController - Checking completion status for ${workoutKeys.length} workouts...');
    for (final key in workoutKeys) {
      final isCompleted = _workoutCompleted[key] ?? false;
      print('🔍 SchedulesController - Workout key "$key": completed=$isCompleted');
      
      // If not completed, check if the key exists in _workoutCompleted at all
      if (!isCompleted && !_workoutCompleted.containsKey(key)) {
        print('⚠️ SchedulesController - Workout key "$key" not found in _workoutCompleted map');
        print('⚠️ SchedulesController - This might indicate a key mismatch between startWorkout() and _checkDayCompletion()');
        print('⚠️ SchedulesController - All workout keys in map: ${_workoutCompleted.keys.toList()}');
      }
    }
    
    // Check if all workouts are completed
    bool allCompleted = workoutKeys.every((key) => _workoutCompleted[key] ?? false);
    print('🔍 SchedulesController - All workouts completed: $allCompleted (required: ${workoutKeys.length} workouts)');
    
    if (!allCompleted) {
      final incompleteWorkouts = workoutKeys.where((key) => !(_workoutCompleted[key] ?? false)).toList();
      print('⚠️ SchedulesController - Incomplete workouts: $incompleteWorkouts');
      print('⚠️ SchedulesController - Day $currentDay is NOT ready for submission - waiting for all workouts to complete');
      return; // Exit early - day is not complete
    }
    
    if (allCompleted && workoutKeys.isNotEmpty) {
      print('✅✅✅ SchedulesController - ========== ALL WORKOUTS COMPLETED FOR DAY $currentDay ==========');
      print('✅✅✅ SchedulesController - Proceeding with submission to backend...');
      print('✅ SchedulesController - ALL WORKOUTS COMPLETED - Proceeding with submission');
      print('✅ SchedulesController - Plan ID: $planId, Day: $currentDay');
      print('✅ SchedulesController - Workout count: ${workoutKeys.length}');
      
      // Mark submission as in progress IMMEDIATELY to prevent duplicate calls
      _isSubmittingCompletion = true;
      _submissionInProgress[submissionKey] = true;
      
      print('🔒 SchedulesController - Submission guard set: _isSubmittingCompletion=true, _submissionInProgress[$submissionKey]=true');
      
      try {
        print('🎉 SchedulesController - ========== DAY $currentDay COMPLETED - STARTING SUBMISSION ==========');
        print('🎉 SchedulesController - Day $currentDay completed! Submitting completion...');
        print('🎉 SchedulesController - Plan ID: $planId');
        print('🎉 SchedulesController - Current Day: $currentDay');
        print('🎉 SchedulesController - Day Workouts: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
        
        // CRITICAL: Submit completion BEFORE updating the day
        // This ensures we submit Day 1 data when currentDay is 1, not Day 2 data
        final submissionSuccess = await _submitDailyTrainingCompletion(activeSchedule, currentDay, dayWorkouts);
        
        // CRITICAL: Only increment day if submission was successful
        if (!submissionSuccess) {
          print('❌ SchedulesController - ========== SUBMISSION FAILED - DAY WILL NOT BE INCREMENTED ==========');
          print('❌ SchedulesController - Day $currentDay completion submission failed');
          print('❌ SchedulesController - Backend returned an error - day will remain at $currentDay');
          print('❌ SchedulesController - User must retry completing Day $currentDay workouts');
          print('❌ SchedulesController - This prevents data loss and incorrect day progression');
          return; // Exit early - don't increment day
        }
        
        print('✅ SchedulesController - Day $currentDay completion submitted successfully');
        
        // CRITICAL: Verify Day 1 was actually completed in database before incrementing
        // This prevents incrementing if backend transaction failed or was rolled back
        final verified = await _verifyDayCompletion(planId, currentDay);
        if (!verified) {
          print('❌ SchedulesController - Day $currentDay completion NOT verified in database');
          print('❌ SchedulesController - Backend may have failed to persist completion');
          print('❌ SchedulesController - NOT incrementing day to prevent data inconsistency');
          print('❌ SchedulesController - User should retry completing Day $currentDay');
          return; // Don't increment day if verification fails
        }
        
        print('✅ SchedulesController - Day $currentDay completion verified in database');
        
        // ONLY AFTER successful submission AND verification, move to next day
        final newDay = currentDay + 1;
        _currentDay[planId.toString()] = newDay;
        _persistCurrentDayToCache(planId, newDay);
        
        // CRITICAL: Verify the day was actually set correctly
        final verifyDay = _currentDay[planId.toString()];
        if (verifyDay != newDay) {
          print('❌ SchedulesController - CRITICAL ERROR: Day increment failed!');
          print('❌ SchedulesController - Expected: $newDay, Actual: $verifyDay');
          print('❌ SchedulesController - Manually setting day to $newDay...');
          _currentDay[planId.toString()] = newDay;
          _persistCurrentDayToCache(planId, newDay);
        }
        
        print('🔍 Day progression: $currentDay → $newDay for plan $planId');
        print('🔍 Current day state: ${_currentDay.value}');
        print('🔍 Verified day for plan $planId: ${_currentDay[planId.toString()]}');
        
        // BACKEND CHANGE: Backend now automatically creates the next day's plan after completion
        // No need for frontend to create it proactively - backend handles it in the transaction
        // Small delay to ensure backend has created Day $newDay before we refresh stats/UI
        print('⏳ SchedulesController - Backend will auto-create Day $newDay plan after transaction commits');
        await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend to create next day
        
        // CRITICAL: Refresh stats after completing a day to ensure stats are updated
        // This ensures that when the app reloads, stats will show the completed workouts
        // Note: Stats are also refreshed in _submitDailyTrainingCompletion, but we refresh here
        // to ensure stats are updated even if the API submission is delayed
        try {
          final statsController = Get.find<StatsController>();
          print('🔄 SchedulesController - Refreshing stats after completing day $currentDay...');
          await statsController.refreshStats(forceSync: true);
          print('✅ SchedulesController - Stats refreshed after completing day $currentDay');
        } catch (e) {
          print('⚠️ SchedulesController - Error refreshing stats after completion: $e');
        }
        
        // Clear completed workouts for next day
        for (String key in workoutKeys) {
          // Cancel timer if active
          _activeTimers[key]?.cancel();
          _activeTimers.remove(key);
          
          _workoutCompleted.remove(key);
          _workoutStarted.remove(key);
          _workoutRemainingMinutes.remove(key);
        }
        
        print('🔍 Moved to day $newDay, cleared workout states');
        
        // CRITICAL: Force UI update to show Day 2
        // Use refreshUI() method to ensure comprehensive UI refresh
        refreshUI();
        
        // Debug: Verify new day state and workouts
        final newDayWorkouts = _getDayWorkouts(activeSchedule, newDay);
        final workoutNames = newDayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList();
        final currentDayAfterIncrement = _currentDay[planId.toString()];
        
        print('🔍 Day $currentDay → Day $newDay transition verification:');
        print('  - Current day in map: $currentDayAfterIncrement (expected: $newDay)');
        print('  - Day $newDay workouts: ${workoutNames.length} workout(s) - ${workoutNames.join(", ")}');
        
        if (currentDayAfterIncrement != newDay) {
          print('❌ SchedulesController - CRITICAL ERROR: Day mismatch after increment!');
          print('❌ SchedulesController - Expected: $newDay, Got: $currentDayAfterIncrement');
          print('❌ SchedulesController - Fixing day value...');
          _currentDay[planId.toString()] = newDay;
          _persistCurrentDayToCache(planId, newDay);
          _currentDay.refresh();
          if (!isClosed) update();
        } else {
          print('✅ SchedulesController - Day increment verified: Day $newDay is correctly set');
        }
        
        // CRITICAL: DO NOT sync with database immediately after completion
        // This prevents triggering another completion check which might submit Day 2
        // The day has already been incremented correctly, so we don't need to sync
        // Sync will happen naturally when the user navigates or the app refreshes
        print('✅ SchedulesController - Day incremented to $newDay - skipping immediate database sync to prevent duplicate submissions');
        
        print('✅✅✅ SchedulesController - ========== DAY $currentDay COMPLETION FLOW FINISHED SUCCESSFULLY ==========');
        print('✅✅✅ SchedulesController - Day $currentDay was submitted to backend');
        print('✅✅✅ SchedulesController - Day incremented from $currentDay to $newDay');
        print('✅✅✅ SchedulesController - API call was made: POST /api/dailyTraining/mobile/complete');
        print('✅✅✅ SchedulesController - UI should now show Day $newDay workouts');
      } catch (e) {
        print('❌❌❌ SchedulesController - ========== ERROR DURING DAY COMPLETION ==========');
        print('❌❌❌ SchedulesController - Day $currentDay completion FAILED - API call was NOT made!');
        print('❌❌❌ SchedulesController - Error during day completion: $e');
        print('❌❌❌ SchedulesController - Error type: ${e.runtimeType}');
        print('❌❌❌ SchedulesController - Error details: ${e.toString()}');
        print('❌❌❌ SchedulesController - Plan ID: $planId, Day: $currentDay');
        print('❌❌❌ SchedulesController - Stack trace: ${StackTrace.current}');
        print('❌❌❌ SchedulesController - Day was NOT incremented due to error');
        print('❌❌❌ SchedulesController - This means Day $currentDay completion was NOT saved to backend!');
        // Don't update day if submission failed
        // Error is logged above - don't rethrow to allow finally block to clear guard
      } finally {
        // Always clear the submission flag, even if there was an error
        print('🔓 SchedulesController - Clearing submission guard: _isSubmittingCompletion=false, removing _submissionInProgress[$submissionKey]');
        _isSubmittingCompletion = false;
        _submissionInProgress.remove(submissionKey);
        print('🔓 SchedulesController - Submission guard cleared');
        print('✅ SchedulesController - Submission guard cleared for plan $planId, day $currentDay');
      }
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
       
        final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
        int? _dayNum(Map dp) => int.tryParse(dp['day_number']?.toString() ?? dp['day']?.toString() ?? '');

        final matchingDay = dailyPlans.firstWhereOrNull((dp) {
          final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
          final dpPlanType = dp['plan_type']?.toString();
          final dayNum = _dayNum(dp);
          final matches = dpPlanId == planId && dayNum == workoutDay && dpPlanType == 'web_assigned';
          if (matches) {
            final exercisesDetails = dp['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
              workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            }
            print('✅ SchedulesController - Found matching daily plan: id=${dp['id']}, day_number=$dayNum, workouts: ${workoutNames.join(", ")}');
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
          print('⚠️ SchedulesController - Could not find daily_plan_id for single workout completion (plan $planId, day $workoutDay)');
          final relevantPlans = dailyPlans.where((dp) {
            final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            return dpPlanId == planId && (dp['plan_type']?.toString() == 'web_assigned');
          }).toList();
          print('⚠️ SchedulesController - Available daily plans for this assignment:');
          for (final dp in relevantPlans) {
            final dpDay = _dayNum(dp);
            final exercisesDetails = dp['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
              workoutNames = exercisesDetails.map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString()).toList();
            }
            print('  - ID: ${dp['id']}, day_number: $dpDay, workouts: ${workoutNames.join(", ")}');
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
        print('❌ SchedulesController - CRITICAL ERROR: Cannot submit completion - daily_plan_id is NULL');
        print('❌ SchedulesController - Plan ID: $planId, Day: $workoutDay, Workout: $workoutName');
        print('❌ SchedulesController - This means the daily_training_plans row for Day $workoutDay does not exist in the database');
        print('❌ SchedulesController - The backend should have created this row when the plan was started');
        print('❌ SchedulesController - Storing completion locally as fallback (will retry later)');
        
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
      
      // CRITICAL: Verify daily_plan_id is valid (not 0 or negative)
      if (dailyPlanId <= 0) {
        print('❌ SchedulesController - CRITICAL ERROR: Invalid daily_plan_id: $dailyPlanId (must be > 0)');
        print('❌ SchedulesController - Plan ID: $planId, Day: $workoutDay, Workout: $workoutName');
        print('❌ SchedulesController - Cannot submit with invalid daily_plan_id');
        return;
      }
      
      print('✅ SchedulesController - daily_plan_id validated: $dailyPlanId (valid for submission)');

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
          planType: 'training',
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
          final planDayNumber = updatedDailyPlan['day_number'] ?? updatedDailyPlan['day'];
          final planType = updatedDailyPlan['plan_type'] as String?;
          
          print('📊 SchedulesController - Single workout completion verification:');
          print('  - daily_plan_id: $dailyPlanId');
          print('  - day_number: $planDayNumber');
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
                // CRITICAL: Pass planType='web_assigned' to ensure we only get assigned plans
                final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
                final matchingDay = dailyPlans.firstWhereOrNull((dp) {
                  final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
                  final dpDayNumber = int.tryParse(dp['day_number']?.toString() ?? dp['day']?.toString() ?? '');
                  final dpPlanType = dp['plan_type']?.toString();
                  return dpPlanId == planId && dpDayNumber == day && dpPlanType == 'web_assigned';
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
              planType: 'training',
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
    final activeSchedule = _activeSchedule.value;
    if (activeSchedule != null) {
      final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
      final currentDay = _currentDay[planId.toString()] ?? 1;
      print('🔄 SchedulesController - Current day for plan $planId: $currentDay');
    }
    _currentDay.refresh();
    _workoutStarted.refresh();
    _workoutCompleted.refresh();
    _workoutRemainingMinutes.refresh();
    _activeSchedule.refresh(); // Also refresh active schedule to trigger UI updates
    if (!isClosed) {
      update();
      // Trigger a second update after a microtask to ensure UI rebuilds
      Future.microtask(() {
        if (!isClosed) {
          _currentDay.refresh();
          update();
          print('🔄 SchedulesController - Second UI update triggered');
        }
      });
    }
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
      
      // Get assignment details (for metadata; day_number is used for matching)
      final assignmentDetails = await getAssignmentDetails(scheduleId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      print('🔍 SchedulesController - Checking if day $day (by day_number) is completed...');
      
      // Get all daily plans for this assignment
      final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final matchingDay = dailyPlans.firstWhereOrNull((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpDayNumber = int.tryParse(dp['day_number']?.toString() ?? dp['day']?.toString() ?? '');
        final dpPlanType = dp['plan_type']?.toString();
        final isStats = dp['is_stats_record'] as bool? ?? false;
        return dpPlanId == scheduleId && dpPlanType == 'web_assigned' && !isStats && dpDayNumber == day;
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
            
            // Cancel timer if active
            _activeTimers[workoutKey]?.cancel();
            _activeTimers.remove(workoutKey);
            
            print('✅ SchedulesController - Marking workout as completed from database: $workoutKey (Day $day)');
            _workoutCompleted[workoutKey] = true;
            _workoutStarted[workoutKey] = false;
            _workoutRemainingMinutes[workoutKey] = 0;
            print('✅ SchedulesController - Marked workout "$workoutName" as completed (key: $workoutKey)');
          }
          
          // Force UI refresh to show completed workouts
          refreshUI();
        }
      } else {
        print('⚠️ SchedulesController - Could not find daily plan for day $day (by day_number, scheduleId: $scheduleId)');
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
      if (userId == 0) {
        print('⚠️ Schedules - No user ID, skipping active schedule load');
        return;
      }
      
      final key = 'activeSchedule_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> snapshot = jsonDecode(data);
        
        // CRITICAL: Validate that the cached schedule belongs to the current user
        final scheduleUserId = snapshot['user_id'] as int?;
        if (scheduleUserId != null && scheduleUserId != userId) {
          print('❌ Schedules - Cached active schedule ${snapshot['id']} belongs to user $scheduleUserId, but current user is $userId - clearing invalid cache');
          await prefs.remove(key);
          _activeSchedule.value = null;
          return;
        }
        
        _activeSchedule.value = snapshot;
        final scheduleId = int.tryParse(snapshot['id']?.toString() ?? '');
        print('📱 Schedules - Loaded active schedule snapshot from cache: ${snapshot['id']} (user_id: $scheduleUserId, validated for current user: $userId)');
        
        // Also load the current day for this schedule (if it exists)
        // IMPORTANT: Calculate resume day using reliable method (don't trust cache)
        if (scheduleId != null) {
          try {
            // CRITICAL: Wait a bit for controllers to initialize before checking database
            // This ensures stats controller is ready when we check for completed days
            await Future.delayed(const Duration(milliseconds: 500));
            print('📱 Schedules - Calculating resume day when restoring active schedule...');
            
            // Use the reliable resume calculation method
            final resumeDay = await _getResumeDay(scheduleId);
            
            _currentDay[scheduleId.toString()] = resumeDay;
            _persistCurrentDayToCache(scheduleId, resumeDay);
            
            print('📱 Schedules - ✅ Restored active schedule: resuming at Day $resumeDay');
          } catch (e) {
            print('⚠️ Schedules - Error calculating resume day when restoring active schedule: $e');
            // If resume calculation fails, fall back to cache
            await _loadCurrentDayFromCache(scheduleId);
            final cachedDay = _currentDay[scheduleId.toString()];
            if (cachedDay != null) {
              print('📱 Schedules - Loaded current day $cachedDay for schedule $scheduleId from cache (after resume calculation error)');
            } else {
              // If no cache, start at Day 1
              _currentDay[scheduleId.toString()] = 1;
              _persistCurrentDayToCache(scheduleId, 1);
              print('📱 Schedules - No cache found, starting at Day 1');
            }
          }
          
          // Refresh stats after restoring active schedule
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

  Future<void> _clearActiveScheduleFromCache() async {
    await _clearActiveScheduleSnapshotIfStopped();
  }

  /// Clear all user data when user logs out or switches users
  /// CRITICAL: This ensures no data from previous user is shown to new user
  Future<void> clearAllUserData() async {
    try {
      print('🧹 SchedulesController - Clearing all user data (user switch/logout)...');
      
      // Clear in-memory state
      _activeSchedule.value = null;
      _startedSchedules.clear();
      _currentDay.clear();
      _workoutStarted.clear();
      _workoutRemainingMinutes.clear();
      _workoutCompleted.clear();
      _completedWorkouts.clear();
      _workoutTimers.clear();
      assignments.clear();
      
      // Clear cache for current user (if available)
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      if (userId > 0) {
        await prefs.remove('activeSchedule_user_$userId');
        await prefs.remove('startedSchedules_user_$userId');
        // Clear all day caches for this user
        final allKeys = prefs.getKeys();
        for (final key in allKeys) {
          if (key.startsWith('schedule_day_') && key.endsWith('_user_$userId')) {
            await prefs.remove(key);
          }
        }
      }
      
      print('✅ SchedulesController - All user data cleared');
    } catch (e) {
      print('❌ SchedulesController - Error clearing user data: $e');
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

  Future<void> _clearCurrentDayFromCache(int scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'schedule_day_${scheduleId}_user_$userId';
      await prefs.remove(key);
    } catch (e) {
      print('❌ Schedules - Error clearing current day from cache: $e');
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

  // Get the last completed day from database by checking completed daily plans (day_number-only)
  Future<int?> _getLastCompletedDayFromDatabase(int scheduleId) async {
    try {
      print('🔍 SchedulesController - Checking database for completed days (day_number) for schedule $scheduleId');

      int? _dayNum(Map p) => int.tryParse(
          p['day_number']?.toString() ?? p['day']?.toString() ?? p['dayNumber']?.toString() ?? '');

      final allPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final assignmentPlans = allPlans.where((plan) {
        final sourceAssignmentId = plan['source_assignment_id'] as int?;
        final sourcePlanId = plan['source_plan_id'] as int?;
        final planType = plan['plan_type'] as String?;
        final isStatsRecord = plan['is_stats_record'] as bool? ?? false;

        if (isStatsRecord) return false;
        final normalizedType = planType?.toLowerCase();
        if (normalizedType == 'manual' || normalizedType == 'ai_generated') return false;

        return sourceAssignmentId == scheduleId || sourcePlanId == scheduleId;
      }).toList();

      print('📅 SchedulesController - Found ${assignmentPlans.length} plans for assignment $scheduleId');

      final completedDayNumbers = <int>[];
      for (final plan in assignmentPlans) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        if (!isCompleted || completedAt == null || completedAt.isEmpty) continue;

        final dn = _dayNum(plan);
        if (dn != null && dn > 0) {
          completedDayNumbers.add(dn);
          print('📅 SchedulesController - Completed plan: id=${plan['id']}, day_number=$dn');
        }
      }

      if (completedDayNumbers.isEmpty) {
        print('📅 SchedulesController - No completed plans found for schedule ');
        return null;
      }

      completedDayNumbers.sort();
      int highestSequential = 0;
      for (final dn in completedDayNumbers.toSet().toList()..sort()) {
        if (dn == highestSequential + 1) {
          highestSequential = dn;
        } else if (dn > highestSequential + 1) {
          break;
        }
      }

      final result = highestSequential > 0 ? highestSequential : null;
      print('📅 SchedulesController - Last sequentially completed day: $result');
      return result;
    } catch (e) {
      print('❌ SchedulesController - Error getting last completed day from database: $e');
      print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // Submit daily training completion to API
  // Returns true if submission was successful, false otherwise
  Future<bool> _submitDailyTrainingCompletion(
    Map<String, dynamic> activeSchedule,
    int currentDay,
    List<Map<String, dynamic>> dayWorkouts,
  ) async {
    print('🚀🚀🚀 SchedulesController - ========== _submitDailyTrainingCompletion() CALLED ==========');
    print('🚀🚀🚀 SchedulesController - This function is responsible for calling the API endpoint');
    print('🚀🚀🚀 SchedulesController - Day: $currentDay');
    print('🚀🚀🚀 SchedulesController - Day workouts count: ${dayWorkouts.length}');
    print('🚀🚀🚀 SchedulesController - Day workouts: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
    
    try {
      final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
      print('🚀🚀🚀 SchedulesController - Plan ID: $planId');
      
      // Align currentDay with backend truth before submitting to avoid out-of-order errors (400 INVALID_COMPLETION_ORDER)
      final lastCompletedDay = await _getLastCompletedDayFromDatabase(planId);
      final expectedDay = (lastCompletedDay ?? 0) + 1; // next sequential day
      print('🔍 SchedulesController - lastCompletedDay=$lastCompletedDay, expectedDay=$expectedDay, currentDay=$currentDay');
      if (expectedDay > 0 && currentDay != expectedDay) {
        print('⚠️ SchedulesController - Day mismatch detected before submit. Aborting to resync: currentDay=$currentDay, expectedDay=$expectedDay');
        // Resync local day and UI so the next attempt targets the correct (next) day
        _currentDay[planId.toString()] = expectedDay;
        _persistCurrentDayToCache(planId, expectedDay);
        refreshUI();
        return false;
      }
      
      // CRITICAL: Validate that we're submitting for the correct day
      // Double-check that the current day hasn't changed during async operations
      final actualCurrentDay = getCurrentDay(planId);
      print('🔍 SchedulesController - Day validation: requested=$currentDay, actual=$actualCurrentDay');
      
      // Only abort if the day has been incremented (which shouldn't happen before submission completes)
      // Allow submission if days match OR if actualCurrentDay is uninitialized (defaults to 1)
      // This prevents false positives from timing issues or initialization
      if (actualCurrentDay != currentDay && actualCurrentDay > currentDay) {
        print('❌ SchedulesController - CRITICAL ERROR: Day mismatch detected!');
        print('❌ SchedulesController - Requested day: $currentDay, Actual current day: $actualCurrentDay');
        print('❌ SchedulesController - Actual day is GREATER than requested - day was incremented before submission!');
        print('❌ SchedulesController - This submission is for the WRONG day - ABORTING to prevent incorrect data storage');
        print('❌ SchedulesController - This likely means the day was updated before submission completed');
        print('❌ SchedulesController - Returning false - submission aborted due to day mismatch');
        return false; // Don't submit if day has been incremented
      } else if (actualCurrentDay != currentDay && actualCurrentDay < currentDay) {
        // If actualCurrentDay is less, it might be uninitialized - log but allow submission
        print('⚠️ SchedulesController - Day mismatch: requested=$currentDay, actual=$actualCurrentDay (actual is less)');
        print('⚠️ SchedulesController - This might be due to initialization - proceeding with submission for day $currentDay');
      }
      
      print('📊 SchedulesController - Submitting daily training completion for plan $planId, day $currentDay');
      print('📊 SchedulesController - Validated: currentDay=$currentDay matches actualCurrentDay=$actualCurrentDay');
      print('📊 SchedulesController - Day workouts being submitted: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
      
      // First, find the correct daily_plan_id for **this specific day** from daily_training_plans using day_number.
      int? dailyPlanId;
      try {
        // Load ALL daily_training_plans for this planId and plan_type='web_assigned' (fresh each submit)
        final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
        final assignmentDailyPlans = allDailyPlans.where((dp) {
          final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
          final dpPlanType = dp['plan_type']?.toString();
          final isStatsRecord = dp['is_stats_record'] as bool? ?? false;

          // Ignore stats rows when resolving daily_plan_id for a given day
          if (isStatsRecord) return false;
          return dpPlanId == planId && dpPlanType == 'web_assigned';
        }).toList();

        print('📅 SchedulesController - Found ${assignmentDailyPlans.length} daily_training_plans rows for plan $planId (web_assigned)');

        // Sort by day_number (fallback to id)
        int? _dayNumLocal(Map p) => int.tryParse(p['day_number']?.toString() ?? p['day']?.toString() ?? '');
        assignmentDailyPlans.sort((a, b) {
          final aDay = _dayNumLocal(a) ?? 99999;
          final bDay = _dayNumLocal(b) ?? 99999;
          if (aDay == bDay) {
            return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
          }
          return aDay.compareTo(bDay);
        });

        print('📅 SchedulesController - Sorted assignmentDailyPlans by day_number for day mapping:');
        for (int i = 0; i < assignmentDailyPlans.length; i++) {
          final dp = assignmentDailyPlans[i];
          print('  - Index ${i + 1}: id=${dp['id']}, daily_plan_id=${dp['daily_plan_id']}, day_number=${dp['day_number'] ?? dp['day']}, is_completed=${dp['is_completed']}, completed_at=${dp['completed_at']}');
        }

        // Find exact match by day_number
        Map<String, dynamic>? matchingRow = assignmentDailyPlans.firstWhereOrNull((dp) {
          final dn = _dayNumLocal(dp);
          return dn == expectedDay;
        });

        if (matchingRow != null) {
          final isCompleted = matchingRow['is_completed'] as bool? ?? false;
          final completedAt = matchingRow['completed_at'] as String?;

          if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
            print('❌ SchedulesController - Target day $expectedDay is already completed (daily_plan_id=${matchingRow['daily_plan_id'] ?? matchingRow['id']})');
            print('❌ SchedulesController - Aborting to avoid resubmitting an already completed day');
            // Resync UI/current day to the next expected day
            final nextDay = expectedDay + 1;
            _currentDay[planId.toString()] = nextDay;
            _persistCurrentDayToCache(planId, nextDay);
            refreshUI();
            return false;
          }

          dailyPlanId = matchingRow['daily_plan_id'] != null
              ? int.tryParse(matchingRow['daily_plan_id']?.toString() ?? '')
              : (matchingRow['id'] != null ? int.tryParse(matchingRow['id']?.toString() ?? '') : null);

          final dpDayNumber = int.tryParse(matchingRow['day_number']?.toString() ?? matchingRow['day']?.toString() ?? '');
          final exercisesDetails = matchingRow['exercises_details'];
          List<String> workoutNames = [];
          if (exercisesDetails is List) {
            workoutNames = exercisesDetails
                .map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString())
                .toList();
          }

          print('✅ SchedulesController - Mapped expected Day $expectedDay → daily_plan_id=$dailyPlanId (day_number=$dpDayNumber, workouts=${workoutNames.join(", ")}, is_completed=$isCompleted)');
        } else {
          print('⚠️ SchedulesController - No daily_training_plans row found for expected Day $expectedDay (plan $planId)');
          print('⚠️ SchedulesController - Will attempt to create on-demand if needed');
          // Don't return here - let it fall through to on-demand creation logic below
        }
      } catch (e) {
        print('⚠️ SchedulesController - Could not resolve daily_plan_id for completion: $e');
      }
      
      if (dailyPlanId == null) {
        print('⚠️ SchedulesController - Could not find daily_plan_id for expected Day $expectedDay (currentDay=$currentDay), creating on-demand');
        print('⚠️ SchedulesController - This should not happen if Day $expectedDay plan was created proactively after Day ${expectedDay - 1} completed');
        // Create daily plan for the expected day on-demand if it doesn't exist
        try {
          // Create the daily plan and get the ID directly from the response
          // Use expectedDay (not currentDay) to ensure we create the correct day
          final createdDailyPlanId = await _createDailyPlanForDay(activeSchedule, expectedDay);
          if (createdDailyPlanId != null) {
            dailyPlanId = createdDailyPlanId;
            print('✅ SchedulesController - Created daily plan on-demand with daily_plan_id: $dailyPlanId for expected Day $expectedDay');
            
            // CRITICAL: Wait a moment for the backend to fully persist the plan before submitting completion
            print('⏳ SchedulesController - Waiting for backend to persist Day $expectedDay plan...');
            await Future.delayed(const Duration(milliseconds: 1000));
            
            // Verify the plan exists before proceeding
            try {
              final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(createdDailyPlanId);
              if (verifyPlan.isNotEmpty) {
                print('✅ SchedulesController - Verified Day $expectedDay plan exists in database before submission');
              } else {
                print('⚠️ SchedulesController - Day $expectedDay plan created but not yet found in database - proceeding anyway');
              }
            } catch (verifyError) {
              print('⚠️ SchedulesController - Could not verify Day $expectedDay plan creation: $verifyError - proceeding anyway');
            }
          } else {
            print('❌ SchedulesController - Failed to create daily plan on-demand - no ID returned');
          }
        } catch (e) {
          print('❌ SchedulesController - Failed to create daily plan on-demand: $e');
          print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
        }
      }
      
      // Don't use planId as fallback - daily_plan_id is required
      if (dailyPlanId == null) {
        print('❌ SchedulesController - CRITICAL ERROR: Cannot submit daily completion - daily_plan_id is NULL');
        print('❌ SchedulesController - Plan ID: $planId, Day: $currentDay');
        print('❌ SchedulesController - This means the daily_training_plans row for Day $currentDay does not exist in the database');
        print('❌ SchedulesController - The backend should have created this row when the plan was started');
        print('❌ SchedulesController - Attempting to create the plan one more time before aborting...');
        
        // Last attempt to create the plan
        try {
          final createdDailyPlanId = await _createDailyPlanForDay(activeSchedule, currentDay);
          if (createdDailyPlanId != null) {
            dailyPlanId = createdDailyPlanId;
            print('✅ SchedulesController - Successfully created daily plan on final attempt: $dailyPlanId');
            await Future.delayed(const Duration(milliseconds: 1000));
          } else {
            print('❌ SchedulesController - Failed to create daily plan on final attempt - aborting submission');
            throw Exception('Cannot submit completion: daily_plan_id is NULL and could not be created');
          }
        } catch (e) {
          print('❌ SchedulesController - Failed to create daily plan on final attempt: $e');
          throw Exception('Cannot submit completion: daily_plan_id is NULL and could not be created: $e');
        }
      }
      
      // CRITICAL: Verify daily_plan_id is valid (not 0 or negative)
      if (dailyPlanId == null || dailyPlanId <= 0) {
        print('❌ SchedulesController - CRITICAL ERROR: Invalid daily_plan_id: $dailyPlanId (must be > 0)');
        print('❌ SchedulesController - Plan ID: $planId, Day: $currentDay');
        print('❌ SchedulesController - Cannot submit with invalid daily_plan_id');
        throw Exception('Invalid daily_plan_id: $dailyPlanId (must be > 0)');
      }
      
      print('✅ SchedulesController - daily_plan_id validated: $dailyPlanId (valid for submission)');
      
      // CRITICAL: Verify that the daily_plan_id corresponds to the correct day BEFORE submission
      // This prevents submitting completion for the wrong day
      try {
        print('🔍 SchedulesController - Verifying daily_plan_id $dailyPlanId corresponds to Day $currentDay...');
        final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
        if (verifyPlan.isNotEmpty) {
          final verifyDay = int.tryParse(verifyPlan['day_number']?.toString() ?? verifyPlan['day']?.toString() ?? '');
          final verifyIsCompleted = verifyPlan['is_completed'] as bool? ?? false;
          final verifyCompletedAt = verifyPlan['completed_at'] as String?;

          if (verifyDay != null && verifyDay != currentDay) {
            print('❌ SchedulesController - CRITICAL ERROR: daily_plan_id $dailyPlanId corresponds to Day $verifyDay, not Day $currentDay!');
            print('❌ SchedulesController - ABORTING submission to prevent incorrect data storage');
            throw Exception('daily_plan_id $dailyPlanId corresponds to Day $verifyDay, not Day $currentDay');
          }

          if (verifyIsCompleted && verifyCompletedAt != null) {
            print('❌ SchedulesController - CRITICAL ERROR: daily_plan_id $dailyPlanId is already marked as completed!');
            print('❌ SchedulesController - completed_at: $verifyCompletedAt');
            print('❌ SchedulesController - This day should not be completed yet - ABORTING submission');
            throw Exception('daily_plan_id $dailyPlanId is already marked as completed');
          }

          print('✅ SchedulesController - Verified daily_plan_id $dailyPlanId corresponds to Day $currentDay and is not yet completed');
        }
      } catch (e) {
        print('❌ SchedulesController - CRITICAL: Validation failed before submission: $e');
        rethrow; // Don't proceed with submission if validation fails
      }
      
      // Create completion data for each workout
      // CRITICAL: Get item IDs from the ASSIGNMENT's exercises_details, not the daily plan's
      // The item_id should be the 1-based index in the assignment's full exercises_details array,
      // not the daily plan's subset. This ensures we submit the correct item_ids that match
      // the backend's expectations.
      Map<String, int> workoutNameToItemId = {};
      List<Map<String, dynamic>> allExercises = [];
      final dayWorkoutNames = dayWorkouts.map((w) => (w['name'] ?? w['workout_name'] ?? '').toString().toLowerCase()).toSet();
      
      try {
        // Get assignment details to access the full exercises_details array
        final assignmentDetails = await getAssignmentDetails(planId);
        Map<String, dynamic> actualPlan = assignmentDetails;
        if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
          actualPlan = assignmentDetails['data'] ?? {};
        }
        
        // Parse the assignment's exercises_details (full array, not daily subset)
        dynamic exercisesDetails = actualPlan['exercises_details'];
        if (exercisesDetails is List && exercisesDetails.isNotEmpty) {
          allExercises = exercisesDetails.cast<Map<String, dynamic>>();
            } else if (exercisesDetails is String) {
              try {
                final parsed = jsonDecode(exercisesDetails);
                if (parsed is List) {
              allExercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                }
              } catch (e) {
            print('⚠️ SchedulesController - Failed to parse assignment exercises_details: $e');
              }
            }
        
        print('📊 SchedulesController - Assignment exercises_details for item_id mapping:');
        print('  - Total exercises in assignment: ${allExercises.length}');
        print('  - Expected workouts for Day $currentDay: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
        
        // Map workout names to item IDs using the ASSIGNMENT's full exercises_details array
        // item_id is the 1-based index in the assignment's exercises_details array
        for (int i = 0; i < allExercises.length; i++) {
          final exercise = allExercises[i];
              // Try multiple name fields to find the workout name
              final workoutName = (exercise['workout_name'] ?? 
                                  exercise['name'] ?? 
                                  exercise['exercise_name'] ?? 
                                  '').toString().trim();
          
          // item_id is the 1-based index in the assignment's exercises_details array
              final itemId = i + 1;
          
          // CRITICAL: Only map workouts that are in dayWorkouts (current day's workouts)
          // This prevents accidentally mapping workouts from other days
          final workoutNameLower = workoutName.toLowerCase();
          final isInDayWorkouts = dayWorkoutNames.contains(workoutNameLower);
          
          if (!isInDayWorkouts) {
            // This workout is not for the current day, skip it
            continue;
          }
          
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
          }
          
          print('✅ SchedulesController - Assignment exercise $i: "$workoutName" → item_id: $itemId (1-based index in assignment array, for Day $currentDay)');
        }
        
        print('🔍 SchedulesController - Mapped ${workoutNameToItemId.length} workout names to item IDs from assignment exercises_details');
        print('🔍 SchedulesController - Available mappings: ${workoutNameToItemId.entries.map((e) => '${e.key}: ${e.value}').join(", ")}');
        
        // Validate that we found item_ids for all dayWorkouts
        for (final workout in dayWorkouts) {
          final workoutName = (workout['name'] ?? workout['workout_name'] ?? '').toString();
          final workoutNameLower = workoutName.toLowerCase();
          if (!workoutNameToItemId.containsKey(workoutNameLower) && !workoutNameToItemId.containsKey(workoutName)) {
            print('⚠️ SchedulesController - WARNING: Could not find item_id for workout "$workoutName" in assignment exercises_details');
            print('⚠️ SchedulesController - This workout might not be in the assignment, or name mismatch');
          }
          }
        } catch (e) {
        print('⚠️ SchedulesController - Could not fetch assignment exercises_details to get item IDs: $e');
        }
      
      final List<Map<String, dynamic>> completionData = [];
      
      // CRITICAL: Validate that dayWorkouts only contains workouts for currentDay
      print('📊 SchedulesController - Validating dayWorkouts for Day $currentDay:');
      print('  - dayWorkouts count: ${dayWorkouts.length}');
      print('  - dayWorkouts names: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
      
      // Verify each workout in dayWorkouts is actually for currentDay
      for (int i = 0; i < dayWorkouts.length; i++) {
        final workout = dayWorkouts[i];
        final workoutName = workout['name'] ?? workout['workout_name'] ?? 'Unknown';
        print('  - Workout $i: $workoutName (for Day $currentDay)');
      }
      
      for (int workoutIndex = 0; workoutIndex < dayWorkouts.length; workoutIndex++) {
        final workout = dayWorkouts[workoutIndex];
        final workoutName = (workout['name'] ?? workout['workout_name'] ?? '').toString();
        final workoutKey = '${planId}_${currentDay}_${workoutName}';
        final remainingMinutes = _workoutRemainingMinutes[workoutKey] ?? 0;
        final totalMinutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
        final actualMinutes = totalMinutes - remainingMinutes;
        
        print('📊 SchedulesController - Processing workout for completion:');
        print('  - Workout: $workoutName');
        print('  - Day: $currentDay');
        print('  - Workout key: $workoutKey');
        print('  - Total minutes: $totalMinutes, Remaining: $remainingMinutes, Actual: $actualMinutes');
        
        // Get item_id as 1-based index in exercises_details array
        // Since daily_training_plan_items table is removed, item_id is now the 1-based array index
        final workoutNameLower = workoutName.toLowerCase();
        
        // Try multiple lookup strategies to find item_id from assignment exercises_details
        int itemId = workoutNameToItemId[workoutNameLower] ?? 
                     workoutNameToItemId[workoutName] ??
                     0;
        
        // CRITICAL: If item_id is 0, try fallback strategies before skipping
        if (itemId == 0) {
          print('⚠️ SchedulesController - Could not find item_id for workout "$workoutName" in assignment exercises_details');
          print('⚠️ SchedulesController - Workout name: "$workoutName" (lowercase: "$workoutNameLower")');
          print('⚠️ SchedulesController - Available mappings: ${workoutNameToItemId.keys.toList()}');
          print('⚠️ SchedulesController - Attempting fallback strategies...');
          
          // FALLBACK 1: Try to find by matching workout properties (sets, reps, weight, minutes)
          bool foundByProperties = false;
          for (int i = 0; i < allExercises.length; i++) {
            final exercise = allExercises[i];
            final exerciseName = (exercise['workout_name'] ?? exercise['name'] ?? exercise['exercise_name'] ?? '').toString().trim();
            final exerciseNameLower = exerciseName.toLowerCase();
            
            // Check if this exercise is in dayWorkouts (same day)
            final isInDayWorkouts = dayWorkoutNames.contains(exerciseNameLower);
            if (!isInDayWorkouts) continue;
            
            // Try to match by properties
            final workoutSets = int.tryParse(workout['sets']?.toString() ?? '0') ?? 0;
            final workoutReps = int.tryParse(workout['reps']?.toString() ?? '0') ?? 0;
            final workoutWeight = double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0;
            final workoutMinutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
            
            final exerciseSets = int.tryParse(exercise['sets']?.toString() ?? '0') ?? 0;
            final exerciseReps = int.tryParse(exercise['reps']?.toString() ?? '0') ?? 0;
            final exerciseWeight = double.tryParse(exercise['weight_kg']?.toString() ?? '0') ?? 0.0;
            final exerciseMinutes = int.tryParse(exercise['minutes']?.toString() ?? '0') ?? 0;
            
            if (workoutSets == exerciseSets && workoutReps == exerciseReps && 
                workoutWeight == exerciseWeight && workoutMinutes == exerciseMinutes) {
              itemId = i + 1; // 1-based index
              foundByProperties = true;
              print('✅ SchedulesController - Found item_id $itemId by matching properties for workout "$workoutName"');
              break;
            }
          }
          
          // FALLBACK 2: Use index in dayWorkouts as last resort (not ideal, but better than skipping)
          if (!foundByProperties && workoutIndex < dayWorkouts.length) {
            // Try to find the workout's position in the assignment's exercises_details
            // by matching it to exercises that are in dayWorkouts
            final dayWorkoutIndex = workoutIndex;
            final matchingDayExercises = <int>[];
            
            for (int i = 0; i < allExercises.length; i++) {
              final exercise = allExercises[i];
              final exerciseName = (exercise['workout_name'] ?? exercise['name'] ?? exercise['exercise_name'] ?? '').toString().trim();
              final exerciseNameLower = exerciseName.toLowerCase();
              if (dayWorkoutNames.contains(exerciseNameLower)) {
                matchingDayExercises.add(i + 1); // 1-based index
              }
            }
            
            if (dayWorkoutIndex < matchingDayExercises.length) {
              itemId = matchingDayExercises[dayWorkoutIndex];
              print('⚠️ SchedulesController - Using fallback: item_id $itemId (index $dayWorkoutIndex in day workouts) for workout "$workoutName"');
              print('⚠️ SchedulesController - This is a fallback - name matching failed, but using position-based item_id');
            } else {
              print('❌ SchedulesController - CRITICAL ERROR: All fallback strategies failed for workout "$workoutName"');
              print('❌ SchedulesController - This workout will NOT be submitted - skipping to prevent incorrect data storage');
              print('❌ SchedulesController - ⚠️ WARNING: If ALL workouts have item_id=0, completionData will be empty and API call will NOT be made!');
              continue; // Skip this workout - all fallbacks failed
            }
          } else if (!foundByProperties) {
            print('❌ SchedulesController - CRITICAL ERROR: All fallback strategies failed for workout "$workoutName"');
            print('❌ SchedulesController - This workout will NOT be submitted - skipping to prevent incorrect data storage');
            print('❌ SchedulesController - ⚠️ WARNING: If ALL workouts have item_id=0, completionData will be empty and API call will NOT be made!');
            continue; // Skip this workout - all fallbacks failed
          }
        } else {
          print('✅ SchedulesController - Found item_id $itemId (1-based index in assignment array) for workout "$workoutName"');
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
      
      // CRITICAL: Final validation - ensure completionData only contains workouts for currentDay
      print('📊 SchedulesController - Final validation before submission:');
      print('  - Current Day: $currentDay');
      print('  - Completion data count: ${completionData.length}');
      print('  - Expected workouts for Day $currentDay: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
      
      // Verify each completion item matches a workout from dayWorkouts
      final dayWorkoutNamesSet = dayWorkouts.map((w) => (w['name'] ?? w['workout_name'] ?? '').toString().toLowerCase()).toSet();
      final invalidCompletions = <int>[];
      
      // Create a map of workout names to their expected item_ids for validation
      final Map<String, int> workoutNameToItemIdMap = {};
      for (int i = 0; i < dayWorkouts.length; i++) {
        final workout = dayWorkouts[i];
        final workoutName = (workout['name'] ?? workout['workout_name'] ?? '').toString();
        final workoutNameLower = workoutName.toLowerCase();
        // Find the item_id for this workout from the mapping we created earlier
        final itemId = workoutNameToItemId[workoutNameLower] ?? workoutNameToItemId[workoutName] ?? 0;
        workoutNameToItemIdMap[workoutNameLower] = itemId;
        print('  - Expected: "$workoutName" → item_id: $itemId');
      }
      
      for (int i = 0; i < completionData.length; i++) {
        final item = completionData[i];
        final itemId = item['item_id'] as int? ?? 0;
        final sets = item['sets_completed'] ?? 0;
        final reps = item['reps_completed'] ?? 0;
        final minutes = item['minutes_spent'] ?? 0;
        
        // Try to match this item_id to a workout name
        String? matchedWorkoutName;
        workoutNameToItemIdMap.forEach((name, id) {
          if (id == itemId) {
            matchedWorkoutName = name;
          }
        });
        
        print('  - Completion item $i: item_id=$itemId, sets=$sets, reps=$reps, minutes=$minutes');
        if (matchedWorkoutName != null) {
          print('    ✅ Matched to workout: "$matchedWorkoutName" (Day $currentDay)');
        } else {
          print('    ⚠️ Could not match item_id $itemId to any Day $currentDay workout');
          invalidCompletions.add(itemId);
        }
      }
      
      if (invalidCompletions.isNotEmpty) {
        print('⚠️ SchedulesController - Found ${invalidCompletions.length} completion items with item_ids that do not match Day $currentDay workouts');
        print('⚠️ SchedulesController - Invalid item_ids: $invalidCompletions');
        print('⚠️ SchedulesController - This suggests workouts from other days might be included!');
      }
      
      if (completionData.length != dayWorkouts.length) {
        print('⚠️ SchedulesController - completionData count (${completionData.length}) does not match dayWorkouts count (${dayWorkouts.length})');
        print('⚠️ SchedulesController - Proceeding anyway; backend ignores completion_data and only needs plan_id/plan_type/is_completed');
      } else {
        print('✅ SchedulesController - Validation passed: completionData count matches dayWorkouts count');
      }
      
      // Allow empty completionData (backend ignores it); just log for visibility
      if (completionData.isEmpty) {
        print('⚠️ SchedulesController - completionData is empty; still submitting completion (backend ignores completion_data)');
      }
      
      // Submit to API using the correct daily_plan_id (dailyPlanId is guaranteed to be non-null at this point)
      try {
        print('📤 SchedulesController - ========== CALLING API: POST /daily-plans/complete ==========');
        print('📤 SchedulesController - Submitting daily training completion to API:');
        print('  - daily_plan_id: $dailyPlanId');
        print('  - plan_type: training');
        print('  - currentDay: $currentDay (ONLY Day $currentDay workouts should be submitted)');
        print('  - completion_data count: ${completionData.length} (ignored by backend)');
        print('📤 SchedulesController - Endpoint: POST /daily-plans/complete');
        print('📤 SchedulesController - Payload: {plan_id: $dailyPlanId, plan_type: training, is_completed: true}');
        
        await _submitCompletionToAPI(
          dailyPlanId: dailyPlanId!,
          planType: 'training',
          isCompleted: true,
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
              final planDayNumber = updatedDailyPlan['day_number'] ?? updatedDailyPlan['day'];
              final planType = updatedDailyPlan['plan_type'] as String?;
              
              print('📊 SchedulesController - Verification result:');
              print('  - is_completed: $isCompleted');
              print('  - completed_at: $completedAt');
              print('  - day_number: $planDayNumber');
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
            print('❌ SchedulesController - CRITICAL ERROR: Completion verification failed after $maxRetries attempts');
            print('❌ SchedulesController - The completion may not have been persisted in the database');
            print('❌ SchedulesController - Backend logs should show transaction commit/rollback status');
            print('❌ SchedulesController - This is a serious issue - the workout completion was not saved');
            // Don't throw here - let the error handling below catch it if needed
            // But log it as a critical error so it's visible in logs
          }
          
          // CRITICAL: Check if backend incorrectly marked OTHER days as completed
          // This is a defensive check to catch backend bugs where completing Day 1 marks Day 2/3 as completed too
          try {
            print('🔍 SchedulesController - Checking for backend bug: verifying ONLY Day $currentDay was marked completed...');
            final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
            final assignmentDailyPlans = allDailyPlans.where((dp) {
              final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
              final dpPlanType = dp['plan_type']?.toString();
              return dpPlanId == planId && dpPlanType == 'web_assigned';
            }).toList();
            
            // Check all assignment plans to see which ones are marked completed (by day_number)
            final incorrectlyCompleted = <Map<String, dynamic>>[];
            for (final dp in assignmentDailyPlans) {
              final dayNum = int.tryParse(dp['day_number']?.toString() ?? dp['day']?.toString() ?? '');
              if (dayNum == null) continue;
              
              final isCompleted = dp['is_completed'] as bool? ?? false;
              final completedAt = dp['completed_at'] as String?;
              final dpId = dp['id'];
              
              if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
                if (dayNum != currentDay) {
                  incorrectlyCompleted.add({
                    'id': dpId,
                    'day': dayNum,
                    'day_number': dayNum,
                    'completed_at': completedAt,
                  });
                }
              }
            }
            
            if (incorrectlyCompleted.isNotEmpty) {
              print('❌ SchedulesController - BACKEND BUG DETECTED: Backend marked ${incorrectlyCompleted.length} OTHER days as completed when only Day $currentDay should be completed!');
              print('❌ SchedulesController - Incorrectly completed days:');
              for (final bad in incorrectlyCompleted) {
                print('  - Day ${bad['day']}: id=${bad['id']}, completed_at=${bad['completed_at']}');
              }
              print('❌ SchedulesController - This is a BACKEND bug - the backend is marking multiple days as completed in a single transaction.');
              print('❌ SchedulesController - Backend should ONLY mark the specific daily_plan_id ($dailyPlanId) as completed, not other days.');
              
              // CRITICAL: Check if the next day (currentDay + 1) is incorrectly marked as completed
              // If so, prevent progression to avoid showing incorrect state
              final nextDay = currentDay + 1;
              final nextDayIncorrectlyCompleted = incorrectlyCompleted.where((bad) => bad['day'] == nextDay).isNotEmpty;
              if (nextDayIncorrectlyCompleted) {
                print('❌ SchedulesController - CRITICAL: Day $nextDay is incorrectly marked as completed!');
                print('❌ SchedulesController - This will prevent the user from starting Day $nextDay workouts.');
                print('❌ SchedulesController - This is a BACKEND bug that needs to be fixed.');
                print('❌ SchedulesController - Frontend cannot fix this - backend must be corrected.');
                // Don't throw - let the error be logged but continue
                // The backend bug needs to be fixed, but we shouldn't crash the app
              }
          } else {
              print('✅ SchedulesController - Verification passed: Only Day $currentDay was marked as completed (no backend bug detected)');
          }
          } catch (e) {
            print('⚠️ SchedulesController - Could not verify if other days were incorrectly marked: $e');
          }
          
          // CRITICAL: Wait a moment for backend transaction to fully commit before syncing stats
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('❌ SchedulesController - CRITICAL ERROR: Failed to submit daily training completion: $e');
          print('❌ SchedulesController - Error type: ${e.runtimeType}');
          print('❌ SchedulesController - Error details: ${e.toString()}');
          print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
          
          // Try to extract error details if it's a DioException-like error
          try {
            final errorStr = e.toString();
            if (errorStr.contains('status code') || errorStr.contains('Status Code')) {
              print('❌ SchedulesController - HTTP error detected');
              // Check for specific backend errors
              if (errorStr.contains('500') || errorStr.contains('isSequentialNextDay')) {
                print('❌ SchedulesController - Backend 500 error detected - this is a backend bug');
                print('❌ SchedulesController - Backend error: isSequentialNextDay is not defined');
                print('❌ SchedulesController - This needs to be fixed in the backend code');
                print('❌ SchedulesController - Completion data will be stored locally and retried later');
              } else if (errorStr.contains('429')) {
                print('❌ SchedulesController - Rate limit error (429) - too many requests');
                print('❌ SchedulesController - Will retry later via retryFailedSubmissions');
              }
            }
          } catch (_) {}
          
          // CRITICAL: Even if API call failed, check if the day was actually completed in the database
          // The backend might have completed the day even though it returned an error (backend bug)
          // This ensures we don't block progression if the backend actually saved the data
          print('🔍 SchedulesController - API call failed, but checking database to see if Day $currentDay was actually completed...');
          bool dayWasActuallyCompleted = false;
          
          if (dailyPlanId != null) {
            try {
              await Future.delayed(const Duration(milliseconds: 1000)); // Wait for backend to potentially save
              final checkDailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
              
              if (checkDailyPlan.isNotEmpty) {
                final isCompleted = checkDailyPlan['is_completed'] as bool? ?? false;
                final completedAt = checkDailyPlan['completed_at'] as String?;
                
                if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
                  dayWasActuallyCompleted = true;
                  print('✅ SchedulesController - Day $currentDay WAS actually completed in database despite API error!');
                  print('✅ SchedulesController - is_completed: $isCompleted, completed_at: $completedAt');
                  print('✅ SchedulesController - Backend completed the day but returned an error (backend bug)');
                  print('✅ SchedulesController - Proceeding with day progression since data was saved');
                } else {
                  print('❌ SchedulesController - Day $currentDay was NOT completed in database');
                  print('❌ SchedulesController - is_completed: $isCompleted, completed_at: ${completedAt != null ? "set" : "null"}');
                }
              }
            } catch (checkError) {
              print('⚠️ SchedulesController - Could not check if day was completed: $checkError');
            }
          }
          
          if (dayWasActuallyCompleted) {
            // Day was completed despite API error - return true to allow progression
            print('✅ SchedulesController - Returning true - day was completed in database, allowing progression');
            return true;
          } else {
            // Day was NOT completed - return false to prevent progression
            print('❌ SchedulesController - ⚠️⚠️⚠️ CRITICAL: Workout completion was NOT saved to database ⚠️⚠️⚠️');
            print('❌ SchedulesController - User completed Day $currentDay workouts but they were not persisted');
            print('❌ SchedulesController - This needs immediate attention - check backend logs and fix the issue');
            print('❌ SchedulesController - Returning false - submission FAILED, day will NOT be incremented');
            return false; // Return false to indicate failure
          }
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
        
        // Return true to indicate successful submission
        print('✅ SchedulesController - Returning true - submission SUCCEEDED, day can be incremented');
        return true;
    } catch (e) {
      print('❌ SchedulesController - Failed to submit daily training completion: $e');
      print('❌ SchedulesController - Error type: ${e.runtimeType}');
      print('❌ SchedulesController - Returning false - submission FAILED, day will NOT be incremented');
      return false; // Return false to indicate failure
    }
  }

  // Refresh schedules data
  Future<void> refreshSchedules() async {
    await loadSchedulesData();
  }

  /// Verify that a specific day was actually completed in the database
  /// This ensures the backend transaction successfully persisted the completion
  /// Returns true if the day is verified as completed, false otherwise
  /// Uses retry logic with delays to handle backend transaction commit timing
  Future<bool> _verifyDayCompletion(int planId, int day) async {
    try {
      print('🔍 SchedulesController - Verifying Day $day completion in database for plan $planId...');
      
      // Get assignment details for start_date to map days correctly
      final assignmentDetails = await getAssignmentDetails(planId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      final startDateStr = actualPlan['start_date']?.toString();
      final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
      final startDateNormalized = startDate != null
          ? DateTime.utc(startDate.year, startDate.month, startDate.day)
          : null;
      
      // Retry logic: Backend transaction may take time to commit
      bool verified = false;
      int retryCount = 0;
      const maxRetries = 5; // More retries since we're checking after submission
      
      while (!verified && retryCount < maxRetries) {
        if (retryCount > 0) {
          // Wait before retrying (increasing delay)
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
        retryCount++;
        
        try {
          // Get all daily plans for this assignment
          final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
          final assignmentDailyPlans = allDailyPlans.where((dp) {
            final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            final dpPlanType = dp['plan_type']?.toString();
            final isStatsRecord = dp['is_stats_record'] as bool? ?? false;
            return dpPlanId == planId && dpPlanType == 'web_assigned' && !isStatsRecord;
          }).toList();
          
          // Sort by day_number (fallback to id)
          int? _dayNum(Map p) => int.tryParse(p['day_number']?.toString() ?? p['day']?.toString() ?? '');
          assignmentDailyPlans.sort((a, b) {
            final ad = _dayNum(a) ?? 999999;
            final bd = _dayNum(b) ?? 999999;
            if (ad == bd) {
              return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
            }
            return ad.compareTo(bd);
          });
          
          // Find the plan for the specified day_number
          final dayPlan = assignmentDailyPlans.firstWhereOrNull((dp) {
            final dn = _dayNum(dp);
            return dn == day;
          });
          
          if (dayPlan != null) {
            final isCompleted = dayPlan['is_completed'] as bool? ?? false;
            final completedAt = dayPlan['completed_at'] as String?;
            
            if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
              print('✅ SchedulesController - Day $day completion verified (attempt $retryCount/$maxRetries): is_completed=true, completed_at=$completedAt');
              verified = true;
            } else {
              print('⚠️ SchedulesController - Day $day completion not yet verified (attempt $retryCount/$maxRetries): is_completed=$isCompleted, completed_at=${completedAt != null ? "set" : "null"}');
              if (retryCount < maxRetries) {
                print('📊 SchedulesController - Retrying verification...');
              }
            }
          } else {
            print('⚠️ SchedulesController - Day $day plan not found in database (attempt $retryCount/$maxRetries, available days: ${assignmentDailyPlans.length})');
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
        print('❌ SchedulesController - Day $day completion NOT verified after $maxRetries attempts');
        print('❌ SchedulesController - Backend may have failed to persist completion or transaction not yet committed');
      }
      
      return verified;
    } catch (e) {
      print('❌ SchedulesController - Error verifying Day $day completion: $e');
      return false;
    }
  }
  
  /// Calculate the resume day for a schedule by finding the highest completed day
  /// This is more reliable than relying on cache or single database queries
  /// Returns the day number (1-based) to resume at, or 1 if no completed days found
  Future<int> _getResumeDay(int scheduleId) async {
    try {
      print('📅 SchedulesController - Calculating resume day for schedule $scheduleId (assigned plan)');

      // 1) Get assignment details for start_date and total days
      final assignmentDetails = await getAssignmentDetails(scheduleId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }

      final startDateStr = actualPlan['start_date']?.toString();
      final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
      final startDateNormalized = startDate != null
          ? DateTime(startDate.year, startDate.month, startDate.day)
          : null;

      // Parse assignment.daily_plans to get total days (for safety clamp)
      final dailyPlansRaw = actualPlan['daily_plans'];
      List<Map<String, dynamic>> assignmentDailyPlans = [];
      if (dailyPlansRaw is String && dailyPlansRaw.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(dailyPlansRaw) as List?;
          if (parsed != null) assignmentDailyPlans = parsed.cast<Map<String, dynamic>>();
        } catch (e) {
          print('⚠️ SchedulesController - Error parsing daily_plans JSON: $e');
        }
      } else if (dailyPlansRaw is List) {
        assignmentDailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
      }
      final totalDays = assignmentDailyPlans.length;

      // 2) Fetch ALL daily_training_plans (include completed) for this assignment, plan_type=web_assigned
      final allPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final schedulePlans = allPlans.where((p) {
        final sourceAssignmentId = p['source_assignment_id'] as int?;
        final sourcePlanId = p['source_plan_id'] as int?;
        final planType = p['plan_type'] as String?;
        final isStats = p['is_stats_record'] as bool? ?? false;
        if (isStats) return false;
        if (planType != 'web_assigned') return false;
        return sourceAssignmentId == scheduleId || sourcePlanId == scheduleId;
      }).toList();

      print('📅 SchedulesController - Found ${schedulePlans.length} daily_training_plans rows for schedule $scheduleId');

      // 3) Find highest completed day using day_number from backend
      int highestCompletedDay = 0;
      for (final plan in schedulePlans) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        if (!isCompleted || completedAt == null || completedAt.isEmpty) continue;

        final dayNumber = int.tryParse(plan['day_number']?.toString() ?? plan['day']?.toString() ?? '');
        if (dayNumber != null && dayNumber > 0 && dayNumber > highestCompletedDay) {
          highestCompletedDay = dayNumber;
          print('✅ SchedulesController - Completed day detected: Day $dayNumber (by day_number)');
        }
      }

      final resumeDay = (highestCompletedDay + 1).clamp(1, totalDays > 0 ? totalDays : 0x7fffffff);
      print('📅 SchedulesController - Resume calculation: highestCompletedDay=$highestCompletedDay, resumeDay=$resumeDay (totalDays=$totalDays)');
      return resumeDay;
    } catch (e) {
      print('❌ SchedulesController - Error calculating resume day: $e');
      print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
      return 1;
    }
  }

  /// Check if a daily plan already exists for a specific day
  /// Returns the daily_plan_id if it exists, null otherwise
  Future<int?> _checkIfDayPlanExists(Map<String, dynamic> schedule, int dayIndex) async {
    try {
      final planId = int.tryParse(schedule['id']?.toString() ?? '') ?? 0;
      if (planId == 0) return null;
      
      print('🔍 SchedulesController - Checking if Day $dayIndex plan exists (by day_number)...');
      
      // Get all daily plans for this assignment
      final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final matchingPlan = allDailyPlans.firstWhereOrNull((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpPlanType = dp['plan_type']?.toString();
        final isStatsRecord = dp['is_stats_record'] as bool? ?? false;
        final dpDayNumber = int.tryParse(dp['day_number']?.toString() ?? dp['day']?.toString() ?? '');
        
        return dpPlanId == planId && 
               dpPlanType == 'web_assigned' && 
               !isStatsRecord &&
               dpDayNumber == dayIndex;
      });
      
      if (matchingPlan != null) {
        final dailyPlanId = matchingPlan['daily_plan_id'] != null
            ? int.tryParse(matchingPlan['daily_plan_id']?.toString() ?? '')
            : (matchingPlan['id'] != null ? int.tryParse(matchingPlan['id']?.toString() ?? '') : null);
        print('✅ SchedulesController - Day $dayIndex plan exists: daily_plan_id=$dailyPlanId');
        return dailyPlanId;
      } else {
        print('ℹ️ SchedulesController - Day $dayIndex plan does not exist yet');
        return null;
      }
    } catch (e) {
      print('⚠️ SchedulesController - Error checking if Day $dayIndex plan exists: $e');
      return null;
    }
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

      // Get assignment details (for metadata; backend now drives by day_number)
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

      print('📤 SchedulesController - Creating daily plan for assigned plan $planId, day_number: $dayIndex');

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
      // - day_number: explicit day index (1-based)
      // - All other columns needed for stats tracking (sets, reps, weight_kg, etc.)
      // For assigned plans, send assignment_id (not approval_id) - backend prioritizes training_plan_assignments
      print('📤 SchedulesController - Sending request to create daily plan with:');
      print('  - assignment_id: $planId');
      print('  - day_number: $dayIndex');
      print('  - web_plan_id: ${webPlanId ?? 'N/A'}');
      print('  - Day workouts count: ${dayWorkouts.length}');
      
      final createdPlan = await _dailyTrainingService.createDailyPlanFromApproval(
        assignmentId: planId, // planId is the assignment ID from training_plan_assignments
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
        
        // CRITICAL: Verify the daily plan was actually created in the database AND matches the requested day
        try {
          await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend to save
          final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          if (verifyPlan.isNotEmpty) {
            final returnedDayNumber = int.tryParse(verifyPlan['day_number']?.toString() ?? verifyPlan['day']?.toString() ?? '');
            if (returnedDayNumber != null && returnedDayNumber != dayIndex) {
              print('❌ SchedulesController - CRITICAL: Daily plan ID $dailyPlanId has wrong day_number!');
              print('❌ Expected day_number: $dayIndex, returned: $returnedDayNumber');
              return null;
            }
            print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId and correct day_number: $dayIndex');
          } else {
            print('⚠️ SchedulesController - Daily plan ID $dailyPlanId was returned but not found in database');
          }
        } catch (verifyError) {
          print('⚠️ SchedulesController - Could not verify daily plan creation: $verifyError');
        }
        
        return dailyPlanId;
      } else {
        // IMPORTANT:
        // We used to call /mobile/plans/find here with (assignmentId + day_number)
        // as a last resort to recover the daily_plan_id. However, backend
        // behavior auto-jumps to the next incomplete day if the requested day_number
        // is already completed.
        //
        // For Schedules, this is dangerous: when we are completing "Day N",
        // we MUST submit completion against the exact daily_plan_id for Day N,
        // not for some later day. Otherwise the database will mark the wrong
        // day as completed (e.g. Day 3) while leaving Day 2 incomplete, which
        // in turn makes restart logic "go backwards" on the next app open.
        //
        // To avoid this mismatch, we NO LONGER use findDailyPlanBySource here.
        // If the ID is missing from the primary response, we simply log and
        // return null instead of guessing.
        print('❌ SchedulesController - Daily plan created but ID not found in response; skipping findDailyPlanBySource to avoid day mismatch');
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
  /// - Finds the last completed daily plan by day_number (not completed_at)
  /// - Skips days with day_number <= lastCompletedDay
  /// - Creates/updates only days after the last completed day_number
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

      // Get assignment details (for metadata; backend now drives by day_number)
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

      // CRITICAL: Create ALL daily plans when plan is started, not just the current day
      // This ensures all days exist in the database from the start
      final currentDay = getCurrentDay(planId);

      // Get total number of days from daily_plans
      final dailyPlansRaw = actualPlan['daily_plans'];
      List<Map<String, dynamic>> dailyPlans = [];
      if (dailyPlansRaw != null) {
        if (dailyPlansRaw is String) {
          try {
            final parsed = jsonDecode(dailyPlansRaw) as List?;
            if (parsed != null) {
              dailyPlans = parsed.cast<Map<String, dynamic>>();
            }
          } catch (e) {
            print('⚠️ SchedulesController - Error parsing daily_plans JSON: $e');
          }
        } else if (dailyPlansRaw is List) {
          dailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
        }
      }

      final totalDays = dailyPlans.length;
      print('📤 SchedulesController - Creating ALL daily plans for assigned plan $planId (total days: $totalDays, creating from Day 1 to Day $totalDays)');
      print('📤 SchedulesController - Current day is Day $currentDay, but creating all days to ensure completeness');

      // Check which days already exist in the database
      final existingPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final existingPlanDays = existingPlans
          .where((p) {
            final dpPlanId = int.tryParse(p['source_plan_id']?.toString() ?? '');
            final isStatsRecord = p['is_stats_record'] as bool? ?? false;
            return dpPlanId == planId && !isStatsRecord;
          })
          .map((p) => int.tryParse(p['day_number']?.toString() ?? p['day']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      print('📤 SchedulesController - Found ${existingPlanDays.length} existing daily plans in database (by day_number)');

      // CRITICAL: Create ALL days from Day 1 to totalDays (don't recreate existing days)
      // This ensures all plans exist in the database from the start, not just from currentDay onwards
      // This prevents issues where plans are missing when completing days
      int createdCount = 0;
      int skippedCount = 0;

      for (int day = 1; day <= totalDays; day++) {
        // Skip if this day's plan already exists
        if (existingPlanDays.contains(day)) {
          print('⏭️ SchedulesController - Skipping Day $day (already exists by day_number)');
          skippedCount++;
          continue;
        }

        print('📤 SchedulesController - Creating daily plan for Day $day (by day_number)...');

      // Log assignment data that should be extracted by backend for stats tracking
      print('📊 SchedulesController - Assignment data available for backend extraction:');
      print('  - Assignment ID: $planId');
      print('  - Category: ${actualPlan['category'] ?? 'N/A'}');
      print('  - User Level: ${actualPlan['user_level'] ?? 'N/A'}');
      print('  - Total Exercises: ${actualPlan['total_exercises'] ?? 0}');
      print('  - Total Workouts: ${actualPlan['total_workouts'] ?? 0}');
      print('  - Training Minutes: ${actualPlan['training_minutes'] ?? 0}');
      print('  - Exercises Details Count: ${actualPlan['exercises_details'] is List ? (actualPlan['exercises_details'] as List).length : 0}');
      
        // Get web_plan_id from schedule if available (backend can use this for lookup)
        final webPlanId = schedule['web_plan_id'] != null 
            ? int.tryParse(schedule['web_plan_id'].toString())
            : null;

        try {
          // Use the new endpoint to create daily plan from assignment
          final createdPlan = await _dailyTrainingService.createDailyPlanFromApproval(
            assignmentId: planId,
            webPlanId: webPlanId,
          );

          if (createdPlan.isNotEmpty) {
            final dailyPlanId = int.tryParse(createdPlan['id']?.toString() ?? '');
            if (dailyPlanId != null) {
              print('✅ SchedulesController - Day $day created successfully (daily_plan_id: $dailyPlanId)');
            } else {
              print('✅ SchedulesController - Day $day created successfully');
            }
            createdCount++;
            
            // Small delay between creations to avoid overwhelming the backend
            if (day < totalDays) {
              await Future.delayed(const Duration(milliseconds: 200));
            }
          } else {
            print('⚠️ SchedulesController - Failed to create Day $day, empty response');
          }
        } catch (e) {
          print('❌ SchedulesController - Failed to create Day $day: $e');
          // Continue creating other days even if one fails
        }
      }

      print('✅ SchedulesController - Daily plan creation complete: $createdCount created, $skippedCount skipped (total days: $totalDays)');
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

    // Note: date is kept for backward compatibility but day_number is the primary identifier
    final DateTime date = startDate.add(Duration(days: dayIndex));
    return {
      'day': dayIndex + 1,
      'day_number': dayIndex + 1, // Primary identifier for day-based system
      'date': date.toIso8601String().split('T').first, // Kept for backward compatibility
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
  /// CRITICAL: Only returns active plans that belong to the current user
  Future<Map<String, dynamic>?> _getAnyActivePlan() async {
    final currentUserId = _profileController.user?.id;
    if (currentUserId == null) {
      print('⚠️ SchedulesController - No current user ID, cannot check for active plans');
      return null;
    }
    
    // Check Schedules tab active plan
    if (_activeSchedule.value != null) {
      final schedule = _activeSchedule.value!;
      final scheduleUserId = schedule['user_id'] as int?;
      
      // CRITICAL: Validate that the active schedule belongs to the current user
      if (scheduleUserId != null && scheduleUserId == currentUserId) {
        print('🔍 SchedulesController - Found active plan in Schedules tab: ${schedule['id']} (user_id: $scheduleUserId matches current user: $currentUserId)');
        return schedule;
      } else {
        print('❌ SchedulesController - Active schedule ${schedule['id']} belongs to user $scheduleUserId, but current user is $currentUserId - clearing invalid active plan');
        // Clear invalid active plan (belongs to different user)
        _activeSchedule.value = null;
        await _clearActiveScheduleFromCache();
      }
    }
    
    // Check Plans tab active plan
    try {
      if (Get.isRegistered<PlansController>()) {
        final plansController = Get.find<PlansController>();
        if (plansController.activePlan != null) {
          final plan = plansController.activePlan!;
          final planUserId = plan['user_id'] as int?;
          
          // CRITICAL: Validate that the active plan belongs to the current user
          if (planUserId != null && planUserId == currentUserId) {
            print('🔍 SchedulesController - Found active plan in Plans tab: ${plan['id']} (user_id: $planUserId matches current user: $currentUserId)');
            return plan;
          } else {
            print('❌ SchedulesController - Active plan ${plan['id']} belongs to user $planUserId, but current user is $currentUserId - this should be cleared by PlansController');
            // Don't clear here - PlansController should handle it, but log the issue
          }
        }
      }
    } catch (e) {
      print('⚠️ SchedulesController - Could not check PlansController: $e');
    }
    
    print('🔍 SchedulesController - No active plans found in any tab for current user: $currentUserId');
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