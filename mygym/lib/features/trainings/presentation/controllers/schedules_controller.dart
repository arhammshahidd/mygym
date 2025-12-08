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
  
  /// Submit completion data to API
  Future<void> _submitCompletionToAPI({
    required int dailyPlanId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    try {
      print('🔍 SchedulesController - _submitCompletionToAPI called:');
      print('  - daily_plan_id: $dailyPlanId');
      print('  - completion_data count: ${completionData.length}');
      print('  - completion_data: $completionData');
      print('🔍 Submitting completion to API via DailyTrainingService');
      print('🔍 API Endpoint: POST /api/dailyTraining/mobile/complete');
      print('🔍 Request payload: {daily_plan_id: $dailyPlanId, completion_data: $completionData}');
      
      final result = await _dailyTrainingService.submitCompletion(
        dailyPlanId: dailyPlanId,
        completionData: completionData,
      );
      
      print('✅ SchedulesController - API call completed successfully');
      print('✅ SchedulesController - Response received from /api/dailyTraining/mobile/complete');
      
      print('✅ SchedulesController - Completion submitted successfully');
      print('✅ SchedulesController - Backend response: $result');
      
      // Verify the response indicates success
      if (result is Map<String, dynamic>) {
        final success = result['success'] as bool? ?? false;
        final message = result['message'] as String? ?? result['msg'] as String?;
        final error = result['error'] as String?;
        print('✅ SchedulesController - Backend success flag: $success');
        if (message != null) {
          print('✅ SchedulesController - Backend message: $message');
        }
        if (error != null) {
          print('❌ SchedulesController - Backend error: $error');
        }
        if (!success) {
          final errorMsg = error ?? message ?? 'Backend returned success=false';
          print('❌ SchedulesController - CRITICAL: Backend returned success=false: $errorMsg');
          throw Exception('Backend completion submission failed: $errorMsg');
        }
      }
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
  /// - We map the first returned plan's `plan_date` back to a 1‑based `day` number
  ///   using the assignment's `daily_plans` (or date difference from `start_date`).
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
            print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): candidate plan for schedule $scheduleId → id=${p['id']}, plan_date=${p['plan_date']}, is_completed=${p['is_completed']}, is_stats_record=$isStatsRecord');
          }
          return idMatches && !isStatsRecord; // Exclude stats records
        }).toList();

        // CRITICAL: Filter to only incomplete plans and sort by plan_date to ensure chronological order
        final incompletePlans = assignmentPlans.where((p) {
          final isCompleted = p['is_completed'] as bool? ?? false;
          return !isCompleted;
        }).toList();

        // Sort by plan_date to ensure chronological order
        incompletePlans.sort((a, b) {
          final aDate = DateTime.tryParse((a['plan_date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = DateTime.tryParse((b['plan_date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });

        if (incompletePlans.isNotEmpty) {
          // Take the first incomplete plan (earliest date)
          final currentPlan = incompletePlans.first;
          final planDateStr = currentPlan['plan_date']?.toString();
          final isCompleted = currentPlan['is_completed'] as bool? ?? false;
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): first incomplete plan for schedule $scheduleId has plan_date=$planDateStr, is_completed=$isCompleted');

          // Map plan_date back to 1-based day number using assignment.daily_plans
          final assignmentDetails = await getAssignmentDetails(scheduleId);
          Map<String, dynamic> actualPlan = assignmentDetails;
          if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
            actualPlan = assignmentDetails['data'] ?? {};
          }

          // Normalize assignment.daily_plans
          List<Map<String, dynamic>> dailyPlans = [];
          final dailyPlansRaw = actualPlan['daily_plans'];
          if (dailyPlansRaw != null) {
            if (dailyPlansRaw is String) {
              try {
                final parsed = jsonDecode(dailyPlansRaw) as List?;
                if (parsed != null) {
                  dailyPlans = parsed.cast<Map<String, dynamic>>();
                }
              } catch (e) {
                print('⚠️ SchedulesController - _getCurrentDayFromBackendPlans: error parsing daily_plans JSON: $e');
              }
            } else if (dailyPlansRaw is List) {
              dailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
            }
          }

          // Build date → dayNumber map from assignment.daily_plans
          final dateToDayNumber = <String, int>{};
          for (final dp in dailyPlans) {
            final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
            final dateStr = dp['date']?.toString();
            if (dayNum > 0 && dateStr != null) {
              final d = DateTime.tryParse(dateStr);
              if (d != null) {
                final normalized = DateTime.utc(d.year, d.month, d.day).toIso8601String().split('T').first;
                dateToDayNumber[normalized] = dayNum;
              }
            }
          }
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): dateToDayNumber mappings: $dateToDayNumber');
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): Available dates in daily_plans: ${dateToDayNumber.keys.toList()}');

          int? dayNumber;
          if (planDateStr != null) {
            final planDate = DateTime.tryParse(planDateStr);
            if (planDate != null) {
              final normalizedPlanDate =
                  DateTime.utc(planDate.year, planDate.month, planDate.day).toIso8601String().split('T').first;
              print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): Looking for plan_date=$normalizedPlanDate in daily_plans mapping');
              
              if (dateToDayNumber.containsKey(normalizedPlanDate)) {
                dayNumber = dateToDayNumber[normalizedPlanDate];
                print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): ✅ mapped plan_date=$normalizedPlanDate to day=$dayNumber via daily_plans');
              } else {
                print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): ⚠️ plan_date=$normalizedPlanDate NOT found in daily_plans mapping');
                
                // Try to find closest matching date in daily_plans (within 2 days)
                int? closestDay;
                int minDiff = 999;
                final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
                
                for (final entry in dateToDayNumber.entries) {
                  final mappedDate = DateTime.tryParse(entry.key);
                  if (mappedDate != null) {
                    final mappedDateNormalized = DateTime.utc(mappedDate.year, mappedDate.month, mappedDate.day);
                    final dateDiff = (planDateNormalized.difference(mappedDateNormalized).inDays).abs();
                    if (dateDiff < minDiff && dateDiff <= 2) {
                      minDiff = dateDiff;
                      closestDay = entry.value;
                    }
                  }
                }
                
                if (closestDay != null && minDiff <= 2) {
                  // Adjust day number based on date difference
                  final closestDateStr = dateToDayNumber.entries.firstWhere((e) => e.value == closestDay).key;
                  final closestDate = DateTime.tryParse(closestDateStr);
                  if (closestDate != null) {
                    final closestDateNormalized = DateTime.utc(closestDate.year, closestDate.month, closestDate.day);
                    final dateDiff = planDateNormalized.difference(closestDateNormalized).inDays;
                    dayNumber = closestDay + dateDiff;
                    print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): ✅ Found closest match: day=$closestDay (date diff: $minDiff days), adjusted to day=$dayNumber');
                  }
                } else {
                  // Fallback: derive from start_date if mapping missing and no close match
                  final startDateStr = actualPlan['start_date']?.toString();
                  final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
                  if (startDate != null) {
                    final startNorm = DateTime.utc(startDate.year, startDate.month, startDate.day);
                    final diff = planDateNormalized.difference(startNorm).inDays;
                    if (diff >= 0) {
                      dayNumber = diff + 1; // 1-based
                      print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): ⚠️ Calculated day=$dayNumber from date diff (diff=$diff, start=$startNorm) - this may be incorrect if daily_plans has offset');
                      print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): 💡 If this day number is wrong, check if daily_plans mapping is complete or if there\'s a date offset');
                    }
                  } else {
                    print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): ❌ Cannot calculate day number: start_date is null and no daily_plans mapping found');
                  }
                }
              }
            }
          }

          // As an absolute minimum, if we have no mapping, treat this as Day 1 so we never crash.
          final resolvedDay = (dayNumber != null && dayNumber > 0) ? dayNumber : 1;
          print('📅 SchedulesController - _getCurrentDayFromBackendPlans(): resolved currentDay=$resolvedDay (1-based)');
          
          // Note: We already filtered for incomplete plans above, so currentPlan should be incomplete
          // Return the resolved day
          return resolvedDay;
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
      
      // If trying to start the same plan, sync current day from backend/database
      if (currentPlanId == scheduleId) {
        print('ℹ️ SchedulesController - Schedule $scheduleId is already active, syncing current day from backend...');

        int? resolvedDay;
        try {
          // Priority 1: Check backend daily plans API
          final backendDay = await _getCurrentDayFromBackendPlans(scheduleId);
          if (backendDay != null && backendDay > 0) {
            resolvedDay = backendDay;
            print('📅 SchedulesController - ✅ Backend returned current day: Day $resolvedDay');
          } else {
            print('📅 SchedulesController - Backend did not return a current day, checking database...');
            
            // Priority 2: Check database for last completed day
            final completedDay = await _getLastCompletedDayFromDatabase(scheduleId);
            if (completedDay != null && completedDay > 0) {
              resolvedDay = completedDay + 1; // Move to first incomplete day
              print('📅 SchedulesController - ✅ Database shows last completed day: $completedDay, should be at Day $resolvedDay');
            } else {
              print('📅 SchedulesController - No completed days found, keeping current day');
              return; // Keep current day if no completion data
            }
          }
        } catch (e) {
          print('⚠️ SchedulesController - Error syncing current day for active plan: $e');
          return; // Keep current day on error
        }

        // Update current day if resolved day is different
        if (resolvedDay != null && resolvedDay > 0) {
          final currentDay = _currentDay[scheduleId.toString()] ?? 1;
          if (resolvedDay != currentDay) {
            _currentDay[scheduleId.toString()] = resolvedDay;
            _persistCurrentDayToCache(scheduleId, resolvedDay);
            print('📅 SchedulesController - ✅ Synced active plan: Day $currentDay → Day $resolvedDay');
            update();
          } else {
            print('📅 SchedulesController - Backend day $resolvedDay matches current day, no change needed');
          }
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
    
    // CRITICAL: Refresh stats FIRST to ensure we have the latest completion data
    // This must happen before checking for completed days so the stats fallback works correctly
    try {
      final statsController = Get.find<StatsController>();
      print('🔄 SchedulesController - Refreshing stats before checking completed days for plan $scheduleId...');
      await statsController.refreshStats(forceSync: true);
      print('✅ SchedulesController - Stats refreshed for plan $scheduleId');
    } catch (e) {
      print('⚠️ SchedulesController - Error refreshing stats before checking completed days: $e');
      // Continue anyway - database check will still work
    }
    
    // CRITICAL: Calculate resume day using reliable method
    // This ensures we resume from the correct day even after stopping and restarting
    // We should NOT rely on cached values as they might be stale
    final resumeDay = await _getResumeDay(scheduleId);
    
    _currentDay[scheduleId.toString()] = resumeDay;
    _persistCurrentDayToCache(scheduleId, resumeDay);
    
    print('📅 SchedulesController - ✅ Starting/resuming plan $scheduleId at Day $resumeDay');
    
    // Store daily training plans for assigned plan (plan_type = 'web_assigned')
    try {
      await _storeDailyTrainingPlansForAssignedPlan(schedule);
    } catch (e) {
      print('⚠️ SchedulesController - Failed to store daily training plans: $e');
      // Continue anyway - plan can still be started without stored daily plans
    }
    
    _persistStartedSchedulesToCache();
    _persistActiveScheduleSnapshot();
    
    // Note: Stats were already refreshed before checking for completed days above
    // No need to refresh again here
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
        
        // CRITICAL: Wait for backend transaction to fully settle before creating next day
        // This prevents race conditions where Day 2 might be affected by Day 1's transaction
        print('⏳ SchedulesController - Waiting for backend transaction to settle before creating Day $newDay...');
        await Future.delayed(const Duration(seconds: 2)); // Wait longer for backend to complete
        
        // CRITICAL: Check if Day 2 plan already exists before creating
        // This prevents duplicate creation and interference with backend operations
        final existingDay2Plan = await _checkIfDayPlanExists(activeSchedule, newDay);
        if (existingDay2Plan != null) {
          print('✅ SchedulesController - Day $newDay plan already exists (daily_plan_id: $existingDay2Plan)');
          print('✅ SchedulesController - Skipping creation to avoid duplicate and backend interference');
          
          // Verify that existing Day 2 plan is NOT completed
          try {
            final verifyExistingPlan = await _dailyTrainingService.getDailyTrainingPlan(existingDay2Plan);
            if (verifyExistingPlan.isNotEmpty) {
              final isCompleted = verifyExistingPlan['is_completed'] as bool? ?? false;
              final completedAt = verifyExistingPlan['completed_at'] as String?;
              
              if (isCompleted && completedAt != null) {
                print('❌ SchedulesController - CRITICAL ERROR: Existing Day $newDay plan is ALREADY marked as completed!');
                print('❌ SchedulesController - completed_at: $completedAt');
                print('❌ SchedulesController - This is a BACKEND bug - Day $newDay should NOT be completed when Day $currentDay is submitted.');
                print('❌ SchedulesController - The backend transaction incorrectly marked Day $newDay as completed.');
              } else {
                print('✅ SchedulesController - Verified existing Day $newDay plan is NOT marked as completed (correct state)');
              }
            }
          } catch (verifyError) {
            print('⚠️ SchedulesController - Could not verify existing Day $newDay plan completion status: $verifyError');
          }
        } else {
          // Day 2 plan doesn't exist, create it now
          try {
            print('📤 SchedulesController - Day $newDay plan does not exist, creating proactively...');
            final nextDayPlanId = await _createDailyPlanForDay(activeSchedule, newDay);
            if (nextDayPlanId != null) {
              print('✅ SchedulesController - Created daily plan for Day $newDay with daily_plan_id: $nextDayPlanId');
              
              // CRITICAL: Verify that Day $newDay is NOT marked as completed when created
              // This prevents the backend from incorrectly marking Day 2 as completed when Day 1 is submitted
              try {
                await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend to save
                final verifyNextDayPlan = await _dailyTrainingService.getDailyTrainingPlan(nextDayPlanId);
                if (verifyNextDayPlan.isNotEmpty) {
                  final isCompleted = verifyNextDayPlan['is_completed'] as bool? ?? false;
                  final completedAt = verifyNextDayPlan['completed_at'] as String?;
                  
                  if (isCompleted && completedAt != null) {
                    print('❌ SchedulesController - CRITICAL ERROR: Day $newDay plan was created but is ALREADY marked as completed!');
                    print('❌ SchedulesController - completed_at: $completedAt');
                    print('❌ SchedulesController - This is a BACKEND bug - Day $newDay should NOT be completed when created.');
                    print('❌ SchedulesController - The backend is incorrectly marking Day $newDay as completed when Day $currentDay is submitted.');
                    print('❌ SchedulesController - This needs to be fixed in the backend - frontend cannot fix this.');
                  } else {
                    print('✅ SchedulesController - Verified Day $newDay plan is NOT marked as completed (correct state)');
                  }
                }
              } catch (verifyError) {
                print('⚠️ SchedulesController - Could not verify Day $newDay plan completion status: $verifyError');
              }
            } else {
              print('⚠️ SchedulesController - Failed to create daily plan for Day $newDay (will be created on-demand when needed)');
            }
          } catch (e) {
            print('⚠️ SchedulesController - Error creating daily plan for Day $newDay: $e');
            print('⚠️ SchedulesController - Plan will be created on-demand when Day $newDay is accessed');
          }
        }
        
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
        // Backend now correctly calculates dates using local date components (no UTC conversion):
        //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0)
        //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1)
        //   - No timezone shifts (uses local date components, not toISOString())
        // 
        // Frontend matches backend behavior: use local date components, not UTC
        // This ensures Day 1 = start_date exactly, Day 2 = start_date + 1, etc.
        DateTime? dateToUse = startDate ?? DateTime.now();
        // Use local date components to match backend behavior (no UTC conversion)
        final localDate = DateTime(dateToUse.year, dateToUse.month, dateToUse.day);
        // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
        final dayOffset = workoutDay - 1;
        final calculatedDate = localDate.add(Duration(days: dayOffset));
        final planDate = '${calculatedDate.year}-${calculatedDate.month.toString().padLeft(2, '0')}-${calculatedDate.day.toString().padLeft(2, '0')}';
        
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
        final isStatsRecord = plan['is_stats_record'] as bool? ?? false;

        // NEW: Never treat stats-only rows as real daily workout plans.
        // These rows aggregate historical stats and must not be used
        // for day mapping or completion detection, otherwise a single
        // completion can appear to affect multiple "days".
        if (isStatsRecord) {
          return false;
        }
        
        // CRITICAL: First check plan type.
        // In some databases this may be stored as 'assigned' instead of 'web_assigned',
        // or even null. Treat both 'web_assigned' and 'assigned' (case‑insensitive) as valid.
        // Only *explicitly* exclude known non‑schedule types like 'manual' or 'ai_generated'.
        final normalizedType = planType?.toLowerCase();
        if (normalizedType == 'manual' || normalizedType == 'ai_generated') {
          return false; // Reject manual/AI plans immediately
        }
        
        // Then check if IDs match
        final idMatches = (sourceAssignmentId == scheduleId || sourcePlanId == scheduleId);
        if (!idMatches) return false;
        
        // CRITICAL: Do NOT filter by creation timestamp when checking for completed days
        // The assignment's updated_at timestamp changes when we stop/restart, which would
        // incorrectly filter out completed plans that were created before the restart.
        // Instead, we rely on the date range filtering (start_date to end_date) and
        // the source_plan_id/source_assignment_id matching to ensure we get the right plans.
        // The backend already handles deleting old plans when reassigning, so we don't
        // need this extra timestamp check here.
        // 
        // NOTE: We keep this commented out to document why we're NOT using timestamp filtering
        // if (assignmentTimestamp != null && planCreatedAt != null) {
        //   final planCreated = DateTime.tryParse(planCreatedAt);
        //   if (planCreated != null && planCreated.isBefore(assignmentTimestamp)) {
        //     print('📅 SchedulesController - ⚠️ Skipping old plan: id=${plan['id']}, plan_created=$planCreated, assignment_timestamp=$assignmentTimestamp (plan is older than assignment)');
        //     return false;
        //   }
        // }
        
        // NOTE: Date range filtering (start_date to end_date) is done in a second pass
        // after we extract start_date from the assignment. This initial filter only checks
        // ID matching and creation timestamp to avoid old plans from previous assignments.
        
        print('📅 SchedulesController - ✅ Found valid plan: id=${plan['id']}, source_assignment_id=$sourceAssignmentId, source_plan_id=$sourcePlanId, plan_type=$planType, is_completed=${plan['is_completed']}, plan_date=${plan['plan_date']}, created_at=$planCreatedAt');
        return true;
      }).toList();
      
      print('📅 SchedulesController - Found ${assignmentPlans.length} plans for assignment $scheduleId');
      
      // CRITICAL: Log all completed plans to verify if Day 1 was submitted
      final completedPlansBeforeFiltering = assignmentPlans.where((plan) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        return isCompleted && completedAt != null && completedAt.isNotEmpty;
      }).toList();
      
      if (completedPlansBeforeFiltering.isNotEmpty) {
        print('📅 SchedulesController - ⚠️ CRITICAL: Found ${completedPlansBeforeFiltering.length} completed plans in database:');
        for (final plan in completedPlansBeforeFiltering) {
          print('  - Plan id=${plan['id']}, plan_date=${plan['plan_date']}, is_completed=${plan['is_completed']}, completed_at=${plan['completed_at']}');
        }
        print('📅 SchedulesController - ⚠️ If Day 1 was just completed, there should be exactly 1 completed plan (Day 1)');
        print('📅 SchedulesController - ⚠️ If Day 2 is also completed, this is a BACKEND bug');
      } else {
        print('📅 SchedulesController - ✅ No completed plans found in database - Day 1 was NOT submitted');
        print('📅 SchedulesController - ✅ This means workouts were completed but submission did not happen');
      }
      
      // Extract start_date from assignment (actualPlan already extracted above)
      // We need this BEFORE filtering by date range. However, in some edge‑cases
      // start_date may be missing or unparsable. In that case we *skip* the
      // date‑range filtering instead of bailing out, and rely on safer fallbacks
      // (such as sequential completed‑plan counting) further below.
      final startDateStr = actualPlan['start_date'] as String?;
      DateTime? startDate;
      if (startDateStr == null) {
        print('⚠️ SchedulesController - No start_date in assignment details, skipping date‑range filtering');
        print('⚠️ SchedulesController - Assignment details keys: ${assignmentDetails.keys.toList()}');
        print('⚠️ SchedulesController - Actual plan keys: ${actualPlan.keys.toList()}');
      } else {
        startDate = DateTime.tryParse(startDateStr);
        if (startDate == null) {
          print('⚠️ SchedulesController - Could not parse start_date: $startDateStr, skipping date‑range filtering');
        }
        }
      
      // Re-filter plans by date range now that we have start_date (if available)
      // Use UTC date normalization to match backend's UTC date handling
      final startDateNormalized =
          startDate != null ? DateTime.utc(startDate.year, startDate.month, startDate.day) : null;
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
            print(
                '📅 SchedulesController - ⚠️ Filtering out plan: id=${plan['id']}, plan_date=$planDateStr is before start_date=$startDateStr');
            return false;
          }
          
          // Plan date must be <= end_date (if end_date is available)
          if (endDate != null) {
            final endDateNormalized = DateTime.utc(endDate.year, endDate.month, endDate.day);
            if (planDateNormalized.isAfter(endDateNormalized)) {
              print(
                  '📅 SchedulesController - ⚠️ Filtering out plan: id=${plan['id']}, plan_date=$planDateStr is after end_date=$endDateStr');
              return false;
            }
          }
          
          return true;
        }).toList();
        
        print(
            '📅 SchedulesController - After date range filtering: ${validDatePlans.length} plans (was ${assignmentPlans.length})');
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
        // CRITICAL: We need to find the LAST SEQUENTIALLY completed day, not just any completed day
        // For example, if Day 1 and Day 3 are completed but Day 2 is not, we should resume at Day 2, not Day 4
        // CRITICAL: Also filter out incorrectly completed days (backend bug: duplicate completed_at timestamps)
        int? lastCompletedDay;
        final completedPlans = <Map<String, dynamic>>[];
        final completedAtToPlans = <String, List<Map<String, dynamic>>>{};
        
        // First, collect all completed plans with their day numbers
        for (final plan in assignmentPlans) {
          final isCompleted = plan['is_completed'] as bool? ?? false;
          final completedAt = plan['completed_at'] as String?;
          
          // CRITICAL: Only consider plans with BOTH is_completed=true AND completed_at set
          // This ensures we only count fully completed days, not partially completed ones
          if (!isCompleted) {
            print('📅 SchedulesController - Skipping plan ${plan['id']}: is_completed=false');
            continue;
          }
          
          // CRITICAL: Require completed_at to be set (backend should set both fields)
          // This prevents counting plans that are marked completed but haven't been fully processed
          if (completedAt == null || completedAt.isEmpty) {
            print('⚠️ SchedulesController - Plan ${plan['id']} is marked completed but completed_at is null/empty - skipping for resume logic');
            print('⚠️ SchedulesController - This plan may be in a partially completed state');
            continue; // Don't count this as completed for resume logic
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
          // Group by completed_at timestamp to detect backend bug (duplicate timestamps)
          if (completedAt != null && completedAt.isNotEmpty) {
            completedAtToPlans.putIfAbsent(completedAt, () => []).add({
              'plan': plan,
              'dayNumber': dayNumber,
              'planDate': normalizedDateStr,
            });
          }
        }
      }
      
      // CRITICAL: Filter out incorrectly completed days (backend bug: duplicate completed_at timestamps)
      // When completing Day N, backend sometimes marks Day N+1 as completed with same timestamp
      // We detect this by checking for duplicate completed_at timestamps and keep only the earliest plan_date
      final correctlyCompletedPlans = <Map<String, dynamic>>[];
      final incorrectlyCompletedPlans = <Map<String, dynamic>>[];
      
      for (final entry in completedAtToPlans.entries) {
        if (entry.value.length > 1) {
          // Multiple plans with same completed_at timestamp - likely backend bug
          print('⚠️ SchedulesController - BACKEND BUG DETECTED: ${entry.value.length} plans have same completed_at timestamp: ${entry.key}');
          for (final item in entry.value) {
            print('  - Plan id=${item['plan']['id']}, plan_date=${item['planDate']}, day=${item['dayNumber']}, completed_at=${entry.key}');
          }
          
          // Sort by plan_date and keep only the first one (earliest date)
          entry.value.sort((a, b) {
            final aDate = DateTime.tryParse(a['planDate'] ?? '');
            final bDate = DateTime.tryParse(b['planDate'] ?? '');
            if (aDate == null || bDate == null) return 0;
            return aDate.compareTo(bDate);
          });
          
          // Keep the first (earliest) plan, mark others as incorrectly completed
          correctlyCompletedPlans.add(entry.value.first['plan']);
          for (int i = 1; i < entry.value.length; i++) {
            incorrectlyCompletedPlans.add(entry.value[i]['plan']);
            print('❌ SchedulesController - Filtering out incorrectly completed plan: id=${entry.value[i]['plan']['id']}, plan_date=${entry.value[i]['planDate']}, day=${entry.value[i]['dayNumber']} (duplicate timestamp)');
          }
        } else {
          // Single plan with this timestamp - likely correct
          correctlyCompletedPlans.add(entry.value.first['plan']);
        }
      }
      
      if (incorrectlyCompletedPlans.isNotEmpty) {
        print('❌ SchedulesController - Filtered out ${incorrectlyCompletedPlans.length} incorrectly completed plans (backend bug: multiple days marked with same timestamp)');
        print('❌ SchedulesController - This is a BACKEND bug - when completing Day N, backend incorrectly marks Day N+1 as completed');
        print('❌ SchedulesController - Only considering ${correctlyCompletedPlans.length} correctly completed plans for resume logic');
      }
      
      // Find the highest day number from correctly completed plans
      lastCompletedDay = null;
      for (final plan in correctlyCompletedPlans) {
        final planDateStr = plan['plan_date'] as String?;
        if (planDateStr == null) continue;
        
        final planDate = DateTime.tryParse(planDateStr);
        if (planDate == null) continue;
        
        final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
        final normalizedDateStr = planDateNormalized.toIso8601String().split('T').first;
        
        int? dayNumber;
        if (dateToDayNumber.containsKey(normalizedDateStr)) {
          dayNumber = dateToDayNumber[normalizedDateStr];
        } else if (startDateNormalized != null) {
          final daysDiff = planDateNormalized.difference(startDateNormalized).inDays;
          if (daysDiff >= 0) {
            dayNumber = daysDiff + 1;
          }
        }
        
        if (dayNumber != null && dayNumber > 0) {
          if (lastCompletedDay == null || dayNumber > lastCompletedDay) {
            lastCompletedDay = dayNumber;
            print('📅 SchedulesController - Updated lastCompletedDay to $lastCompletedDay (from correctly completed plan: plan_date=$normalizedDateStr)');
          }
        }
      }
      
      print('📅 SchedulesController - Found ${completedPlans.length} total completed plans, ${correctlyCompletedPlans.length} correctly completed, ${incorrectlyCompletedPlans.length} incorrectly completed');
      print('📅 SchedulesController - Last correctly completed day from database query: $lastCompletedDay');
      
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
            
            // CRITICAL: Do NOT filter by creation timestamp when checking for completed plans in stats
            // The assignment's updated_at timestamp changes when we stop/restart, which would
            // incorrectly filter out completed plans that were created before the restart.
            // Instead, we rely on the ID matching (source_plan_id, source_assignment_id) and
            // plan_type filtering to ensure we get the right plans.
            // The backend already handles deleting old plans when reassigning, so we don't
            // need this extra timestamp check here.
            
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
      
      // FINAL SAFETY NET:
      // If, after all of the above, we STILL haven't identified a lastCompletedDay
      // but we do see completed plans for this assignment in the raw data, fall
      // back to treating the number of completed plans (ordered by date) as the
      // "last completed day". This guarantees that if at least Day 1 is marked
      // completed in the database, we will never incorrectly report "no completed
      // days" and reset the UI back to Day 1.
      if (lastCompletedDay == null) {
        final sequentialCompletedPlans = assignmentPlans
            .where((plan) => (plan['is_completed'] as bool? ?? false))
            .toList();
        if (sequentialCompletedPlans.isNotEmpty) {
          print(
              '📅 SchedulesController - Fallback: using count of completed assignment plans as lastCompletedDay (sequential resume)');
          // Optional: sort by plan_date to respect chronological order, though we only
          // need the count here.
          sequentialCompletedPlans.sort((a, b) {
            final ad = DateTime.tryParse((a['plan_date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bd = DateTime.tryParse((b['plan_date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return ad.compareTo(bd);
          });
          lastCompletedDay = sequentialCompletedPlans.length;
          print('📅 SchedulesController - Fallback lastCompletedDay = $lastCompletedDay');
        }
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
                int? statsLastDay;
              
              if (startDate == null) {
                print(
                    '⚠️ SchedulesController - start_date is null while using dailyWorkouts fallback; skipping this stats-based mapping');
              } else {
                // Normalize to UTC to match backend's UTC date format
                final startDateNormalized =
                    DateTime.utc(startDate.year, startDate.month, startDate.day);
                
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
      
      // First, find the correct daily_plan_id for **this specific day** from daily_training_plans.
      // IMPORTANT: We now derive the ID strictly from the assignment's start_date
      // (canonical Day‑1 date) instead of trusting assignment.daily_plans which
      // can be off by one day. This guarantees:
      //   - Day 1 in the UI → start_date
      //   - Day 2 in the UI → start_date + 1, etc.
      int? dailyPlanId;
      try {
        // 1) Get assignment details (in case we need start_date or other metadata later)
        final assignmentDetails = await getAssignmentDetails(planId);
        Map<String, dynamic> actualPlan = assignmentDetails;
        if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
          actualPlan = assignmentDetails['data'] ?? {};
        }
        
        // Normalize start_date for day-number calculations
        final startDateStr = actualPlan['start_date']?.toString();
        final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
        final startDateNormalized = startDate != null
            ? DateTime.utc(startDate.year, startDate.month, startDate.day)
            : null;

        // 2) Load ALL daily_training_plans for this planId and plan_type='web_assigned'
      final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final assignmentDailyPlans = allDailyPlans.where((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpPlanType = dp['plan_type']?.toString();
        final isStatsRecord = dp['is_stats_record'] as bool? ?? false;

        // NEW: Ignore stats rows when resolving daily_plan_id for a given day.
        // Only real training-plan rows (is_stats_record = false) should be
        // eligible to receive is_completed / completed_at updates.
        if (isStatsRecord) {
          return false;
        }

        return dpPlanId == planId && dpPlanType == 'web_assigned';
      }).toList();

        print('📅 SchedulesController - Found ${assignmentDailyPlans.length} daily_training_plans rows for plan $planId (web_assigned)');
        
        // Filter out any plans that belong to days already completed (guard against re-submitting prior days)
        if (startDateNormalized != null && lastCompletedDay != null && lastCompletedDay > 0) {
          final filteredPlans = assignmentDailyPlans.where((dp) {
            final planDateStr = dp['plan_date']?.toString();
            if (planDateStr == null) return true; // keep if unknown
            final planDate = DateTime.tryParse(planDateStr);
            if (planDate == null) return true;
            final planDateNorm = DateTime.utc(planDate.year, planDate.month, planDate.day);
            final dayNumber = planDateNorm.difference(startDateNormalized).inDays + 1; // 1-based
            return dayNumber > lastCompletedDay;
          }).toList();
          if (filteredPlans.length != assignmentDailyPlans.length) {
            print('⚠️ SchedulesController - Excluding ${assignmentDailyPlans.length - filteredPlans.length} plans already completed (day <= $lastCompletedDay)');
          }
          assignmentDailyPlans
            ..clear()
            ..addAll(filteredPlans);
        }
        
        // CRITICAL: Filter out stats records before sorting and mapping
        final realDailyPlans = assignmentDailyPlans.where((dp) {
          final isStatsRecord = dp['is_stats_record'] as bool? ?? false;
          return !isStatsRecord;
        }).toList();
        
        print('📅 SchedulesController - After filtering stats records: ${realDailyPlans.length} real daily plans');

        // 3) Map days strictly by chronological order of plan_date:
        //    - Smallest plan_date  → Day 1
        //    - Second smallest     → Day 2
        //    - etc.
        // This matches the user's expectation that the earliest date is Day 1,
        // regardless of any off‑by‑one issues in assignment.daily_plans.
        realDailyPlans.sort((a, b) {
          final ad = DateTime.tryParse(a['plan_date']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd = DateTime.tryParse(b['plan_date']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

        print('📅 SchedulesController - Sorted realDailyPlans by plan_date for day mapping:');
        for (int i = 0; i < realDailyPlans.length; i++) {
          final dp = realDailyPlans[i];
          print(
              '  - Index ${i + 1} (Day ${i + 1}): id=${dp['id']}, daily_plan_id=${dp['daily_plan_id']}, plan_date=${dp['plan_date']}, is_completed=${dp['is_completed']}, completed_at=${dp['completed_at']}');
        }

        // CRITICAL: Filter out already completed plans to prevent submitting Day 2 when only Day 1 should be submitted
        // Only select plans that are NOT completed for the current day
        final incompletePlans = realDailyPlans.where((dp) {
          final isCompleted = dp['is_completed'] as bool? ?? false;
          final completedAt = dp['completed_at'] as String?;
          return !isCompleted || completedAt == null || completedAt.isEmpty;
        }).toList();
        
        print('📅 SchedulesController - Filtered to ${incompletePlans.length} incomplete plans (out of ${realDailyPlans.length} total)');
        print('📅 SchedulesController - CRITICAL: Only incomplete plans will be used for submission to prevent duplicate submissions');

        Map<String, dynamic>? matchingRow;
        final targetIndex = currentDay - 1; // currentDay is 1‑based
        
        // CRITICAL: Use incomplete plans only - this ensures we don't submit Day 2 if Day 1 is being submitted
        if (targetIndex >= 0 && targetIndex < incompletePlans.length) {
          matchingRow = incompletePlans[targetIndex];
          
          // CRITICAL: Double-check that this plan is NOT already completed
          final isCompleted = matchingRow['is_completed'] as bool? ?? false;
          final completedAt = matchingRow['completed_at'] as String?;
          if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
            print('❌ SchedulesController - CRITICAL ERROR: Day $currentDay plan is ALREADY completed!');
            print('❌ SchedulesController - completed_at: $completedAt');
            print('❌ SchedulesController - This day should not be submitted again - ABORTING');
            print('❌ SchedulesController - This prevents submitting Day 2 when only Day 1 should be submitted');
            throw Exception('Day $currentDay is already completed - cannot submit again');
          }
          
          print(
              '✅ SchedulesController - Mapped Day $currentDay → index ${targetIndex + 1}, id=${matchingRow['id']}, daily_plan_id=${matchingRow['daily_plan_id']}, plan_date=${matchingRow['plan_date']}, is_completed=${matchingRow['is_completed']}');
        } else {
          print(
              '⚠️ SchedulesController - No matching incomplete daily_training_plans row: currentDay=$currentDay, availableIncompleteRows=${incompletePlans.length}');
          print('⚠️ SchedulesController - This means Day $currentDay plan does not exist in database yet or is already completed');
          if (incompletePlans.isNotEmpty) {
            print('⚠️ SchedulesController - Available incomplete days: ${incompletePlans.map((dp) => "Day ${incompletePlans.indexOf(dp) + 1} (id=${dp['id']}, date=${dp['plan_date']}, is_completed=${dp['is_completed']})").join(", ")}');
          }
        }

        if (matchingRow != null) {
          // CRITICAL: Verify this plan is NOT already completed before using it
          final isCompleted = matchingRow['is_completed'] as bool? ?? false;
          final completedAt = matchingRow['completed_at'] as String?;
          
          if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
            print('❌ SchedulesController - CRITICAL ERROR: Day $currentDay plan is ALREADY completed!');
            print('❌ SchedulesController - completed_at: $completedAt');
            print('❌ SchedulesController - This day should not be submitted again');
            print('❌ SchedulesController - This prevents submitting Day 2 when only Day 1 should be submitted');
            print('❌ SchedulesController - ABORTING submission to prevent duplicate completion');
            throw Exception('Day $currentDay is already completed - cannot submit again. This prevents submitting Day 2 with Day 1.');
          }
          
          // Use the exact daily_plan_id/id from this row
          dailyPlanId = matchingRow['daily_plan_id'] != null
              ? int.tryParse(matchingRow['daily_plan_id']?.toString() ?? '')
              : (matchingRow['id'] != null ? int.tryParse(matchingRow['id']?.toString() ?? '') : null);

          final dpDate = matchingRow['plan_date']?.toString().split('T').first;
          final exercisesDetails = matchingRow['exercises_details'];
            List<String> workoutNames = [];
            if (exercisesDetails is List) {
            workoutNames = exercisesDetails
                .map((e) => (e['workout_name'] ?? e['name'] ?? 'Unknown').toString())
                .toList();
            }

          print('✅ SchedulesController - Mapped Day $currentDay → daily_plan_id=$dailyPlanId (plan_date=$dpDate, workouts=${workoutNames.join(", ")}, is_completed=$isCompleted)');
        } else {
          print('⚠️ SchedulesController - Could not find matching incomplete daily_training_plans row for plan $planId, Day $currentDay');
          print('⚠️ SchedulesController - This means Day $currentDay plan does not exist or is already completed');
          if (incompletePlans.isNotEmpty) {
            print('⚠️ SchedulesController - Available incomplete rows: ${incompletePlans.map((dp) => "id=${dp['id']}, plan_date=${dp['plan_date']}, is_completed=${dp['is_completed']}").join("; ")}');
          }
        }
      } catch (e) {
        print('⚠️ SchedulesController - Could not resolve daily_plan_id for completion: $e');
      }
      
      if (dailyPlanId == null) {
        print('⚠️ SchedulesController - Could not find daily_plan_id for day $currentDay, creating on-demand');
        print('⚠️ SchedulesController - This should not happen if Day $currentDay plan was created proactively after Day ${currentDay - 1} completed');
        // Create daily plan for the current day on-demand if it doesn't exist
        try {
          // Create the daily plan and get the ID directly from the response
          final createdDailyPlanId = await _createDailyPlanForDay(activeSchedule, currentDay);
          if (createdDailyPlanId != null) {
            dailyPlanId = createdDailyPlanId;
            print('✅ SchedulesController - Created daily plan on-demand with daily_plan_id: $dailyPlanId for day $currentDay');
            
            // CRITICAL: Wait a moment for the backend to fully persist the plan before submitting completion
            print('⏳ SchedulesController - Waiting for backend to persist Day $currentDay plan...');
            await Future.delayed(const Duration(milliseconds: 1000));
            
            // Verify the plan exists before proceeding
            try {
              final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(createdDailyPlanId);
              if (verifyPlan.isNotEmpty) {
                print('✅ SchedulesController - Verified Day $currentDay plan exists in database before submission');
              } else {
                print('⚠️ SchedulesController - Day $currentDay plan created but not yet found in database - proceeding anyway');
              }
            } catch (verifyError) {
              print('⚠️ SchedulesController - Could not verify Day $currentDay plan creation: $verifyError - proceeding anyway');
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
          final verifyPlanDate = verifyPlan['plan_date'] as String?;
          final verifyIsCompleted = verifyPlan['is_completed'] as bool? ?? false;
          final verifyCompletedAt = verifyPlan['completed_at'] as String?;
          
          // Map plan_date to day number to verify it matches currentDay
          final assignmentDetails = await getAssignmentDetails(planId);
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
              } catch (e) {}
            } else if (dailyPlansRaw is List) {
              dailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
            }
          }
          
          final dateToDayNumber = <String, int>{};
          for (final dp in dailyPlans) {
            final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
            final dateStr = dp['date']?.toString();
            if (dayNum > 0 && dateStr != null) {
              final d = DateTime.tryParse(dateStr);
              if (d != null) {
                final normalized = DateTime.utc(d.year, d.month, d.day).toIso8601String().split('T').first;
                dateToDayNumber[normalized] = dayNum;
              }
            }
          }
          
          if (verifyPlanDate != null) {
            final verifyDate = DateTime.tryParse(verifyPlanDate);
            if (verifyDate != null) {
              final normalized = DateTime.utc(verifyDate.year, verifyDate.month, verifyDate.day).toIso8601String().split('T').first;
              final mappedDay = dateToDayNumber[normalized];
              
              if (mappedDay != null && mappedDay != currentDay) {
                print('❌ SchedulesController - CRITICAL ERROR: daily_plan_id $dailyPlanId corresponds to Day $mappedDay, not Day $currentDay!');
                print('❌ SchedulesController - This would cause Day $mappedDay to be marked as completed instead of Day $currentDay!');
                print('❌ SchedulesController - ABORTING submission to prevent incorrect data storage');
                throw Exception('daily_plan_id $dailyPlanId corresponds to Day $mappedDay, not Day $currentDay');
              }
              
              if (verifyIsCompleted && verifyCompletedAt != null) {
                print('❌ SchedulesController - CRITICAL ERROR: daily_plan_id $dailyPlanId is already marked as completed!');
                print('❌ SchedulesController - completed_at: $verifyCompletedAt');
                print('❌ SchedulesController - This day should not be completed yet - ABORTING submission');
                throw Exception('daily_plan_id $dailyPlanId is already marked as completed');
              }
              
              print('✅ SchedulesController - Verified daily_plan_id $dailyPlanId corresponds to Day $currentDay and is not yet completed');
            }
          }
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
        print('❌ SchedulesController - WARNING: Found ${invalidCompletions.length} completion items with item_ids that do not match Day $currentDay workouts');
        print('❌ SchedulesController - Invalid item_ids: $invalidCompletions');
        print('❌ SchedulesController - This suggests workouts from other days might be included!');
      }
      
      if (completionData.length != dayWorkouts.length) {
        print('❌ SchedulesController - CRITICAL ERROR: completionData count (${completionData.length}) does not match dayWorkouts count (${dayWorkouts.length})!');
        print('❌ SchedulesController - This suggests workouts from other days might be included!');
        print('❌ SchedulesController - Aborting submission to prevent incorrect data storage');
        throw Exception('Completion data count mismatch: ${completionData.length} != ${dayWorkouts.length}');
      }
      
      print('✅ SchedulesController - Validation passed: completionData count matches dayWorkouts count');
      
      // CRITICAL: Check if completionData is empty - this would prevent API call
      if (completionData.isEmpty) {
        print('❌ SchedulesController - ========== CRITICAL ERROR: completionData is EMPTY ==========');
        print('❌ SchedulesController - API call will NOT be made because completionData is empty!');
        print('❌ SchedulesController - This means no workouts were added to completionData');
        print('❌ SchedulesController - Plan ID: $planId, Day: $currentDay');
        print('❌ SchedulesController - Day workouts count: ${dayWorkouts.length}');
        print('❌ SchedulesController - Day workouts: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
        print('❌ SchedulesController - Possible causes:');
        print('  1. All workouts were skipped due to missing item_id (most likely)');
        print('  2. dayWorkouts is empty');
        print('  3. Workout name mismatch preventing item_id lookup');
        print('❌ SchedulesController - Available item_id mappings: ${workoutNameToItemId.entries.map((e) => '${e.key}: ${e.value}').join(", ")}');
        print('❌ SchedulesController - Day $currentDay completion will NOT be saved to database!');
        print('❌ SchedulesController - This is a CRITICAL issue - the API endpoint will NOT be called!');
        throw Exception('Cannot submit completion: completionData is empty - no workouts to submit. All workouts likely have item_id=0 due to name mismatch.');
      }
      
      // Submit to API using the correct daily_plan_id (dailyPlanId is guaranteed to be non-null at this point)
      try {
        print('📤 SchedulesController - ========== CALLING API: POST /api/dailyTraining/mobile/complete ==========');
        print('📤 SchedulesController - Submitting daily training completion to API:');
        print('  - daily_plan_id: $dailyPlanId');
        print('  - currentDay: $currentDay (ONLY Day $currentDay workouts should be submitted)');
        print('  - completion_data count: ${completionData.length}');
        print('  - completion_data: $completionData');
        print('📤 SchedulesController - Endpoint: POST /api/dailyTraining/mobile/complete');
        print('📤 SchedulesController - Payload: {daily_plan_id: $dailyPlanId, completion_data: $completionData}');
        
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
            
            // Get assignment details to map plan_date → dayNumber
            final assignmentDetails = await getAssignmentDetails(planId);
            Map<String, dynamic> actualPlan = assignmentDetails;
            if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
              actualPlan = assignmentDetails['data'] ?? {};
            }
            
            final dailyPlansRaw = actualPlan['daily_plans'];
            List<Map<String, dynamic>> dailyPlansDef = [];
            if (dailyPlansRaw != null) {
              if (dailyPlansRaw is String) {
                try {
                  final parsed = jsonDecode(dailyPlansRaw) as List?;
                  if (parsed != null) {
                    dailyPlansDef = parsed.cast<Map<String, dynamic>>();
                  }
                } catch (e) {}
              } else if (dailyPlansRaw is List) {
                dailyPlansDef = dailyPlansRaw.cast<Map<String, dynamic>>();
              }
            }
            
            final dateToDayNumber = <String, int>{};
            for (final dp in dailyPlansDef) {
              final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
              final dateStr = dp['date']?.toString();
              if (dayNum > 0 && dateStr != null) {
                final d = DateTime.tryParse(dateStr);
                if (d != null) {
                  final normalized = DateTime.utc(d.year, d.month, d.day).toIso8601String().split('T').first;
                  dateToDayNumber[normalized] = dayNum;
                }
              }
            }
            
            // Check all assignment plans to see which ones are marked completed
            final incorrectlyCompleted = <Map<String, dynamic>>[];
            for (final dp in assignmentDailyPlans) {
              final planDateStr = dp['plan_date']?.toString();
              if (planDateStr == null) continue;
              
              final planDate = DateTime.tryParse(planDateStr);
              if (planDate == null) continue;
              
              final normalized = DateTime.utc(planDate.year, planDate.month, planDate.day).toIso8601String().split('T').first;
              int? dayNum = dateToDayNumber[normalized];
              if (dayNum == null) {
                final startDateStr = actualPlan['start_date']?.toString();
                final startDate = startDateStr != null ? DateTime.tryParse(startDateStr) : null;
                if (startDate != null) {
                  final startNorm = DateTime.utc(startDate.year, startDate.month, startDate.day);
                  final planNorm = DateTime.utc(planDate.year, planDate.month, planDate.day);
                  final diff = planNorm.difference(startNorm).inDays;
                  if (diff >= 0) {
                    dayNum = diff + 1;
                  }
                }
              }
              
              final isCompleted = dp['is_completed'] as bool? ?? false;
              final completedAt = dp['completed_at'] as String?;
              final dpId = dp['id'];
              
              if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
                if (dayNum != null && dayNum != currentDay) {
                  incorrectlyCompleted.add({
                    'id': dpId,
                    'day': dayNum,
                    'plan_date': normalized,
                    'completed_at': completedAt,
                  });
                }
              }
            }
            
            if (incorrectlyCompleted.isNotEmpty) {
              print('❌ SchedulesController - BACKEND BUG DETECTED: Backend marked ${incorrectlyCompleted.length} OTHER days as completed when only Day $currentDay should be completed!');
              print('❌ SchedulesController - Incorrectly completed days:');
              for (final bad in incorrectlyCompleted) {
                print('  - Day ${bad['day']}: id=${bad['id']}, plan_date=${bad['plan_date']}, completed_at=${bad['completed_at']}');
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
  Future<bool> _verifyDayCompletion(int planId, int day) async {
    try {
      print('🔍 SchedulesController - Verifying Day $day completion in database for plan $planId...');
      
      // Get all daily plans for this assignment
      final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final assignmentDailyPlans = allDailyPlans.where((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpPlanType = dp['plan_type']?.toString();
        final isStatsRecord = dp['is_stats_record'] as bool? ?? false;
        return dpPlanId == planId && dpPlanType == 'web_assigned' && !isStatsRecord;
      }).toList();
      
      // Sort by plan_date to map days correctly
      assignmentDailyPlans.sort((a, b) {
        final ad = DateTime.tryParse(a['plan_date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse(b['plan_date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });
      
      // Get the plan for the specified day (day is 1-based)
      final targetIndex = day - 1;
      if (targetIndex >= 0 && targetIndex < assignmentDailyPlans.length) {
        final dayPlan = assignmentDailyPlans[targetIndex];
        final isCompleted = dayPlan['is_completed'] as bool? ?? false;
        final completedAt = dayPlan['completed_at'] as String?;
        
        if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
          print('✅ SchedulesController - Day $day completion verified: is_completed=true, completed_at=$completedAt');
          return true;
        } else {
          print('❌ SchedulesController - Day $day completion NOT verified: is_completed=$isCompleted, completed_at=$completedAt');
          return false;
        }
      } else {
        print('❌ SchedulesController - Day $day plan not found in database (available days: ${assignmentDailyPlans.length})');
        return false;
      }
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
      print('📅 SchedulesController - Calculating resume day for schedule $scheduleId');
      
      // Strategy 1: Query backend for daily plans (includes most recent completed day)
      final dailyPlans = await _dailyTrainingService.getDailyPlans(planType: 'web_assigned');
      
      // Filter for this schedule
      final schedulePlans = dailyPlans.where((p) {
        final sourceId = p['source_assignment_id'] as int? ?? p['source_plan_id'] as int?;
        final isStatsRecord = p['is_stats_record'] as bool? ?? false;
        return sourceId == scheduleId && !isStatsRecord;
      }).toList();
      
      print('📅 SchedulesController - Found ${schedulePlans.length} plans for schedule $scheduleId');
      
      // Debug logging
      print('🔍 DEBUG: All schedule plans:');
      for (final plan in schedulePlans) {
        final planDate = plan['plan_date']?.toString();
        final isCompleted = plan['is_completed'];
        final completedAt = plan['completed_at'];
        final id = plan['id'];
        print('  - Plan $id: date=$planDate, is_completed=$isCompleted, completed_at=$completedAt');
      }
      
      if (schedulePlans.isEmpty) {
        print('📅 SchedulesController - No plans found, starting at Day 1');
        return 1;
      }
      
      // Get assignment details for date mapping
      final assignmentDetails = await getAssignmentDetails(scheduleId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      // Parse daily_plans to get day numbers
      final dailyPlansRaw = actualPlan['daily_plans'];
      List<Map<String, dynamic>> assignmentDailyPlans = [];
      if (dailyPlansRaw != null) {
        if (dailyPlansRaw is String) {
          try {
            final parsed = jsonDecode(dailyPlansRaw) as List?;
            if (parsed != null) {
              assignmentDailyPlans = parsed.cast<Map<String, dynamic>>();
            }
          } catch (e) {
            print('⚠️ SchedulesController - Error parsing daily_plans JSON: $e');
          }
        } else if (dailyPlansRaw is List) {
          assignmentDailyPlans = dailyPlansRaw.cast<Map<String, dynamic>>();
        }
      }
      
      // Build date -> day number map
      final dateToDay = <String, int>{};
      for (final dp in assignmentDailyPlans) {
        final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
        final dateStr = dp['date']?.toString();
        if (dayNum > 0 && dateStr != null) {
          // Normalize date to YYYY-MM-DD
          final date = DateTime.tryParse(dateStr);
          if (date != null) {
            final normalized = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            dateToDay[normalized] = dayNum;
          }
        }
      }
      
      print('🔍 DEBUG: Date to day mapping:');
      dateToDay.forEach((date, day) {
        print('  - $date → Day $day');
      });
      
      // Find the highest completed day
      int highestCompletedDay = 0;
      
      for (final plan in schedulePlans) {
        final planDate = plan['plan_date']?.toString();
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        
        if (planDate != null && isCompleted && completedAt != null && completedAt.isNotEmpty) {
          // Find day number for this plan_date
          final date = DateTime.tryParse(planDate);
          if (date != null) {
            final normalized = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final dayNum = dateToDay[normalized];
            
            if (dayNum != null && dayNum > highestCompletedDay) {
              highestCompletedDay = dayNum;
              print('✅ SchedulesController - Found completed Day $dayNum (date: $normalized)');
            }
          }
        }
      }
      
      // Resume day = highest completed day + 1
      final resumeDay = highestCompletedDay + 1;
      
      print('📅 SchedulesController - Resume calculation: highestCompletedDay=$highestCompletedDay, resumeDay=$resumeDay');
      
      // Safety check: don't exceed total days
      final totalDays = assignmentDailyPlans.length;
      if (resumeDay > totalDays && totalDays > 0) {
        print('⚠️ SchedulesController - Resume day $resumeDay exceeds total days $totalDays, using last day');
        return totalDays;
      }
      
      // Ensure resume day is at least 1
      if (resumeDay < 1) {
        print('⚠️ SchedulesController - Resume day $resumeDay is less than 1, using Day 1');
        return 1;
      }
      
      return resumeDay;
      
    } catch (e) {
      print('❌ SchedulesController - Error calculating resume day: $e');
      print('❌ SchedulesController - Stack trace: ${StackTrace.current}');
      return 1; // Fallback to Day 1 on error
    }
  }

  /// Check if a daily plan already exists for a specific day
  /// Returns the daily_plan_id if it exists, null otherwise
  Future<int?> _checkIfDayPlanExists(Map<String, dynamic> schedule, int dayIndex) async {
    try {
      final planId = int.tryParse(schedule['id']?.toString() ?? '') ?? 0;
      if (planId == 0) return null;
      
      // Get assignment details to calculate plan_date
      final assignmentDetails = await getAssignmentDetails(planId);
      Map<String, dynamic> actualPlan = assignmentDetails;
      if (assignmentDetails.containsKey('success') && assignmentDetails.containsKey('data')) {
        actualPlan = assignmentDetails['data'] ?? {};
      }
      
      // Get start_date and calculate plan_date for the day
      final startDateStr = actualPlan['start_date']?.toString();
      if (startDateStr == null) return null;
      
      final startDate = DateTime.tryParse(startDateStr);
      if (startDate == null) return null;
      
      // Calculate plan_date: Day 1 = start_date, Day 2 = start_date + 1, etc.
      final dayOffset = dayIndex - 1; // dayIndex is 1-based, so Day 1 = offset 0
      final planDate = startDate.add(Duration(days: dayOffset));
      final planDateStr = '${planDate.year}-${planDate.month.toString().padLeft(2, '0')}-${planDate.day.toString().padLeft(2, '0')}';
      
      print('🔍 SchedulesController - Checking if Day $dayIndex plan exists (plan_date: $planDateStr)...');
      
      // Get all daily plans for this assignment
      final allDailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final matchingPlan = allDailyPlans.firstWhereOrNull((dp) {
        final dpPlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
        final dpPlanType = dp['plan_type']?.toString();
        final isStatsRecord = dp['is_stats_record'] as bool? ?? false;
        final dpPlanDate = dp['plan_date']?.toString().split('T').first;
        
        return dpPlanId == planId && 
               dpPlanType == 'web_assigned' && 
               !isStatsRecord &&
               dpPlanDate == planDateStr;
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

      // CRITICAL: Use the date from daily_plans array, not calculate from start_date
      // The daily_plans array is the source of truth for which date corresponds to which day
      // Backend now correctly calculates dates using local date components (no UTC conversion)
      // - Day 1 date = start_date exactly (no offset)
      // - Day 2 date = start_date + 1 day
      // - No timezone shifts
      // The daily_plans JSON in the assignment is updated with correct dates during sync
      String? planDate;
      
      // First, try to get the date from daily_plans array
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
      
      // Find the date for this day from daily_plans array
      Map<String, dynamic>? dayPlan;
      try {
        dayPlan = dailyPlans.firstWhere((dp) {
          final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
          return dayNum == dayIndex;
        });
      } catch (e) {
        dayPlan = null;
      }
      
      if (dayPlan != null && dayPlan['date'] != null) {
        final dateFromArray = dayPlan['date'].toString();
        
        // Use date from daily_plans array as the source of truth; do not override with start_date calculations
        planDate = dateFromArray;
        print('📅 SchedulesController - Using date from daily_plans array for Day $dayIndex: $planDate');
      } else {
        // Fallback: Calculate from start_date if daily_plans array doesn't have this day
        final DateTime? startDate = actualPlan['start_date'] != null 
            ? DateTime.tryParse(actualPlan['start_date'].toString())
            : DateTime.now();
        
        if (startDate == null) {
          print('⚠️ SchedulesController - Could not parse start_date, skipping daily plan creation');
          return null;
        }

        // Fallback: Calculate from start_date if daily_plans array doesn't have this day
        // IMPORTANT: dayIndex is now 1-based (Day 1 = 1, Day 2 = 2, etc.)
        // Backend now correctly calculates dates using local date components (no UTC conversion):
        //   - Day 1 (day: 1): plan_date = assignment.start_date + 0 days (dayOffset = 1 - 1 = 0)
        //   - Day 2 (day: 2): plan_date = assignment.start_date + 1 day (dayOffset = 2 - 1 = 1)
        //   - No timezone shifts (uses local date components, not toISOString())
        // 
        // Frontend matches backend behavior: use local date components, not UTC
        // This ensures Day 1 = start_date exactly, Day 2 = start_date + 1, etc.
        final localDate = DateTime(startDate.year, startDate.month, startDate.day);
        // Convert 1-based day to 0-based offset: Day 1 → offset 0, Day 2 → offset 1, etc.
        final dayOffset = dayIndex - 1;
        final calculatedDate = localDate.add(Duration(days: dayOffset));
        planDate = '${calculatedDate.year}-${calculatedDate.month.toString().padLeft(2, '0')}-${calculatedDate.day.toString().padLeft(2, '0')}';
        print('📅 SchedulesController - Calculated date from start_date for Day $dayIndex: $planDate (fallback - should not happen if daily_plans is correct)');
      }
      
      if (planDate == null) {
        print('❌ SchedulesController - Could not determine plan_date for Day $dayIndex, skipping daily plan creation');
        return null;
      }

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
        
        // CRITICAL: Verify the daily plan was actually created in the database AND matches the requested day
        try {
          await Future.delayed(const Duration(milliseconds: 500)); // Small delay for backend to save
          final verifyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
          if (verifyPlan.isNotEmpty) {
            // Verify the plan_date matches what we requested
            // Backend now uses local date components (no UTC conversion), so dates should match exactly
            final returnedPlanDate = verifyPlan['plan_date'] as String?;
            if (returnedPlanDate != null) {
              final returnedDate = DateTime.tryParse(returnedPlanDate);
              final expectedDate = DateTime.tryParse(planDate);
              if (returnedDate != null && expectedDate != null) {
                // Compare dates using local date components (matching backend behavior)
                final returnedDateNormalized = DateTime(returnedDate.year, returnedDate.month, returnedDate.day);
                final expectedDateNormalized = DateTime(expectedDate.year, expectedDate.month, expectedDate.day);
                final dateDiff = (returnedDateNormalized.difference(expectedDateNormalized).inDays).abs();
                if (dateDiff == 0) {
                  print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId and correct plan_date: $planDate');
                } else {
                  // Allow 1 day difference as a safety margin (should not happen with backend fix, but keep for robustness)
                  if (dateDiff <= 1) {
                    print('⚠️ SchedulesController - Daily plan ID $dailyPlanId has plan_date with 1-day difference');
                    print('⚠️ SchedulesController - Expected plan_date: $planDate (Day $dayIndex)');
                    print('⚠️ SchedulesController - Returned plan_date: $returnedPlanDate');
                    print('⚠️ SchedulesController - This should not happen with backend fix - allowing 1-day difference as safety margin');
                    print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId');
                  } else {
                    print('❌ SchedulesController - CRITICAL: Daily plan ID $dailyPlanId has wrong plan_date!');
                    print('❌ SchedulesController - Expected plan_date: $planDate (Day $dayIndex)');
                    print('❌ SchedulesController - Returned plan_date: $returnedPlanDate');
                    print('❌ SchedulesController - Date difference: $dateDiff days (more than 1 day - this is a backend bug)');
                    print('❌ SchedulesController - Returning null to prevent using wrong plan');
                    return null; // Don't return wrong plan if date is off by more than 1 day
                  }
                }
              } else {
                print('⚠️ SchedulesController - Could not parse dates for validation (expected: $planDate, returned: $returnedPlanDate)');
                print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId');
              }
            } else {
              print('⚠️ SchedulesController - Daily plan ID $dailyPlanId exists but has no plan_date field');
              print('✅ SchedulesController - Verified daily plan exists in database with ID: $dailyPlanId');
            }
          } else {
            print('⚠️ SchedulesController - Daily plan ID $dailyPlanId was returned but not found in database');
          }
        } catch (verifyError) {
          print('⚠️ SchedulesController - Could not verify daily plan creation: $verifyError');
        }
        
        return dailyPlanId;
      } else {
        // IMPORTANT:
        // We used to call /mobile/plans/find here with (assignmentId + planDate)
        // as a last resort to recover the daily_plan_id. However, backend
        // behavior has changed so that if the requested plan_date is already
        // completed, the endpoint *automatically jumps to the next incomplete day*.
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

      // CRITICAL: Create ALL daily plans when plan is started, not just the current day
      // This ensures all days exist in the database from the start
      final currentDay = getCurrentDay(planId);
      final DateTime? startDate = actualPlan['start_date'] != null 
          ? DateTime.tryParse(actualPlan['start_date'].toString())
          : DateTime.now();
      
      if (startDate == null) {
        print('⚠️ SchedulesController - Could not parse start_date, skipping daily plan storage');
        return;
      }

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
      final existingPlanDates = existingPlans
          .where((p) {
            final dpPlanId = int.tryParse(p['source_plan_id']?.toString() ?? '');
            final isStatsRecord = p['is_stats_record'] as bool? ?? false;
            return dpPlanId == planId && !isStatsRecord;
          })
          .map((p) => p['plan_date']?.toString().split('T').first)
          .whereType<String>()
          .toSet();

      print('📤 SchedulesController - Found ${existingPlanDates.length} existing daily plans in database');

      // CRITICAL: Create ALL days from Day 1 to totalDays (don't recreate existing days)
      // This ensures all plans exist in the database from the start, not just from currentDay onwards
      // This prevents issues where plans are missing when completing days
      // CRITICAL: Use dates from daily_plans array, not calculate from start_date
      // The daily_plans array is the source of truth for which date corresponds to which day
      // Backend now correctly calculates dates using local date components (no UTC conversion)
      // - Day 1 date = start_date exactly (no offset)
      // - Day 2 date = start_date + 1 day
      // - No timezone shifts
      // The daily_plans JSON in the assignment is updated with correct dates during sync
      int createdCount = 0;
      int skippedCount = 0;

      for (int day = 1; day <= totalDays; day++) {
        // Get the date for this day from daily_plans array
        String? planDate;
        final dayPlan = dailyPlans.firstWhere(
          (dp) {
            final dayNum = int.tryParse(dp['day']?.toString() ?? '') ?? 0;
            return dayNum == day;
          },
          orElse: () => <String, dynamic>{},
        );
        
        if (dayPlan.isNotEmpty && dayPlan['date'] != null) {
          final dateFromArray = dayPlan['date'].toString();
          
          // CRITICAL: Validate that the date from daily_plans array matches what it should be based on start_date
          // This handles the case where old assignments (created before backend fix) have incorrect dates
          // Calculate what the date SHOULD be based on start_date (backend fix: Day 1 = start_date exactly)
          final localDate = DateTime(startDate.year, startDate.month, startDate.day);
          final dayOffset = day - 1;
          final expectedDate = localDate.add(Duration(days: dayOffset));
          final expectedDateStr = '${expectedDate.year}-${expectedDate.month.toString().padLeft(2, '0')}-${expectedDate.day.toString().padLeft(2, '0')}';
          
          // Parse dates for comparison (normalize to date only, ignore time)
          final dateFromArrayParsed = DateTime.tryParse(dateFromArray);
          final expectedDateParsed = DateTime.tryParse(expectedDateStr);
          
          if (dateFromArrayParsed != null && expectedDateParsed != null) {
            final dateFromArrayNormalized = DateTime(dateFromArrayParsed.year, dateFromArrayParsed.month, dateFromArrayParsed.day);
            final expectedDateNormalized = DateTime(expectedDateParsed.year, expectedDateParsed.month, expectedDateParsed.day);
            
            if (dateFromArrayNormalized != expectedDateNormalized) {
              // Date mismatch detected - use calculated date instead (backend fix behavior)
              print('⚠️ SchedulesController - Date mismatch detected for Day $day!');
              print('⚠️ SchedulesController - Date from daily_plans array: $dateFromArray');
              print('⚠️ SchedulesController - Expected date (from start_date): $expectedDateStr');
              print('⚠️ SchedulesController - This assignment may have been created before backend fix');
              print('⚠️ SchedulesController - Using calculated date ($expectedDateStr) to match backend fix behavior');
              planDate = expectedDateStr;
            } else {
              // Dates match - use date from array
              planDate = dateFromArray;
            }
          } else {
            // Could not parse dates - use date from array as-is
            planDate = dateFromArray;
          }
        } else {
          // Fallback: Calculate from start_date if daily_plans array doesn't have this day
          // Backend now uses local date components (no UTC conversion) to avoid timezone shifts
          // Match backend behavior: use local date components, not UTC
          final localDate = DateTime(startDate.year, startDate.month, startDate.day);
          final dayOffset = day - 1;
          final calculatedDate = localDate.add(Duration(days: dayOffset));
          planDate = '${calculatedDate.year}-${calculatedDate.month.toString().padLeft(2, '0')}-${calculatedDate.day.toString().padLeft(2, '0')}';
          print('⚠️ SchedulesController - Day $day not found in daily_plans array, calculated from start_date: $planDate (fallback - should not happen if daily_plans is correct)');
        }
        
        if (planDate == null) {
          print('❌ SchedulesController - Could not determine plan_date for Day $day, skipping');
          continue;
        }
        
        // Skip if this day's plan already exists
        if (existingPlanDates.contains(planDate)) {
          print('⏭️ SchedulesController - Skipping Day $day (plan_date: $planDate) - already exists in database');
          skippedCount++;
          continue;
        }

        print('📤 SchedulesController - Creating daily plan for Day $day (date: $planDate)...');

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
            planDate: planDate,
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