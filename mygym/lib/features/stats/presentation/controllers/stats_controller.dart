import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../trainings/data/services/daily_training_service.dart';
import '../../../trainings/domain/models/daily_training_plan.dart';
import '../../../trainings/presentation/controllers/schedules_controller.dart';
import '../../../trainings/presentation/controllers/plans_controller.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../../shared/services/realtime_service.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../domain/models/user_stats.dart';

class StatsController extends GetxController {
  final DailyTrainingService _dailyTrainingService = DailyTrainingService();
  final RealtimeService _realtime = RealtimeService();
  final AuthService _authService = AuthService();
  final ProfileController _profileController = Get.find<ProfileController>();
  bool _socketSubscribed = false;

  // Stats data
  final RxBool isLoading = false.obs;
  final RxBool hasLoadedOnce = false.obs;
  final RxList<DailyTrainingPlan> dailyPlans = <DailyTrainingPlan>[].obs;
  // Store raw JSON data from daily plans to extract stats fields (training_minutes, etc.)
  final RxList<Map<String, dynamic>> dailyPlansRaw = <Map<String, dynamic>>[].obs;
  final Rx<UserStats?> userStats = Rx<UserStats?>(null);
  // Keep legacy TrainingStats for backward compatibility if needed
  final Rx<TrainingStats?> trainingStats = Rx<TrainingStats?>(null);
  
  // Local cache for offline access
  final RxMap<String, dynamic> _cachedStats = <String, dynamic>{}.obs;
  final RxList<Map<String, dynamic>> _cachedRecentWorkouts = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> _localCompletions = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    _loadCachedStats();
    _loadLocalCompletions();
    // Realtime updates are not supported by current RealtimeService API in this module.
    // We rely on explicit refresh calls after workout completion.
  }

  @override
  void onClose() {
    // No realtime connection to close here
    super.onClose();
  }

  // Realtime not used in current implementation
  Future<void> _subscribeToRealtimeUpdates() async {}
  void _handleRealtimeUpdate(Map<String, dynamic> data) {}

  Future<void> _loadCachedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      
      // Load cached stats
      final cachedStatsJson = prefs.getString('cached_training_stats_user_$userId');
      if (cachedStatsJson != null) {
        final cachedStats = jsonDecode(cachedStatsJson) as Map<String, dynamic>;
        _cachedStats.assignAll(cachedStats);
        
        // Load cached recent workouts
        final cachedWorkoutsJson = prefs.getString('cached_recent_workouts_user_$userId');
        if (cachedWorkoutsJson != null) {
          final cachedWorkouts = jsonDecode(cachedWorkoutsJson) as List<dynamic>;
          _cachedRecentWorkouts.assignAll(cachedWorkouts.cast<Map<String, dynamic>>());
        }
      }
    } catch (e) {
      print('❌ Stats - Error loading cached stats: $e');
    }
  }

  Future<void> _persistCachedStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      
      await prefs.setString('cached_training_stats_user_$userId', jsonEncode(_cachedStats));
      await prefs.setString('cached_recent_workouts_user_$userId', jsonEncode(_cachedRecentWorkouts));
    } catch (e) {
      print('❌ Stats - Error persisting cached stats: $e');
    }
  }

  Future<void> loadStatsData() async {
    try {
      print('📊 Stats - Starting loadStatsData...');
      isLoading.value = true;
      
      // Ensure profile is loaded
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      print('👤 Stats - User ID: $userId');
      
      if (userId == null || userId == 0) {
        print('❌ Stats - No valid user ID');
        return;
      }

      // Get active plan type to fetch correct stats record
      final activePlanIds = _getActivePlanSourceIds();
      String? planType = activePlanIds?['planType'] as String?;
      
      // CRITICAL: Validate planType is set when there's an active plan
      if (activePlanIds != null && (planType == null || planType.isEmpty)) {
        print('⚠️ Stats - CRITICAL ERROR: Active plan found but planType is null or empty!');
        print('⚠️ Stats - Active plan IDs: $activePlanIds');
        print('⚠️ Stats - This will cause backend to return stats for wrong plan type (likely web_assigned)');
        print('⚠️ Stats - Attempting to infer planType from active plan data...');
        
        // Try to infer planType from active plan
        if (Get.isRegistered<PlansController>()) {
          final plansController = Get.find<PlansController>();
          if (plansController.activePlan != null) {
            final plan = plansController.activePlan!;
            final planTypeFromField = plan['plan_type']?.toString().toLowerCase();
            if (planTypeFromField == 'ai_generated' || planTypeFromField == 'manual') {
              planType = planTypeFromField;
              print('✅ Stats - Inferred planType from active plan: $planType');
            } else {
              // Check AI indicators
              final isAiPlan = plan.containsKey('ai_generated') || 
                              plan.containsKey('gemini_generated') ||
                              plan.containsKey('ai_plan_id') ||
                              plan.containsKey('request_id') ||
                              (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
              planType = isAiPlan ? 'ai_generated' : 'manual';
              print('✅ Stats - Inferred planType from AI indicators: $planType');
            }
          }
        } else if (Get.isRegistered<SchedulesController>()) {
          planType = 'web_assigned';
          print('✅ Stats - Inferred planType as web_assigned (active schedule found)');
        }
      }
      
      if (planType != null && planType.isNotEmpty) {
        print('📊 Stats - Active plan type detected: $planType');
        print('📊 Stats - Will fetch stats for plan type: $planType');
        print('📊 Stats - API call: GET /api/stats/mobile?planType=$planType');
      } else {
        print('📊 Stats - No active plan detected - clearing stats data');
        // No active plan, clear all stats to show empty state
        userStats.value = null;
        trainingStats.value = null;
        dailyPlans.clear();
        dailyPlansRaw.clear();
        isLoading.value = false;
        print('✅ Stats - Stats cleared (no active plan)');
        return;
      }
      
      // Fetch user statistics using new API endpoint
      // Backend now creates separate stats records per plan type
      // CRITICAL: planType is guaranteed to be non-null at this point
      try {
        print('📊 Stats - Fetching user statistics from /api/stats/mobile with planType=$planType...');
        final statsData = await _dailyTrainingService.getStats(refresh: false, planType: planType!);
        print('📊 Stats - User stats result: $statsData');
        print('📊 Stats - User stats type: ${statsData.runtimeType}');
        
        if (statsData is Map<String, dynamic>) {
          // API returns {success: true, data: {...}} or just {...}
          final dataToParse = statsData['data'] as Map<String, dynamic>? ?? statsData;
          userStats.value = UserStats.fromJson(dataToParse);
          _cachedStats.assignAll(dataToParse);
          print('✅ Stats - User stats updated');
          print('✅ Stats - Total workouts: ${userStats.value?.totalWorkouts}');
          print('✅ Stats - Total minutes: ${userStats.value?.totalMinutes}');
          print('✅ Stats - Longest streak: ${userStats.value?.longestStreak}');
          print('📊 Stats - Daily workouts dates: ${userStats.value?.dailyWorkouts.keys.toList()}');
          print('📊 Stats - Daily workouts data: ${userStats.value?.dailyWorkouts}');
          
          // Also update legacy TrainingStats for backward compatibility
          trainingStats.value = _convertUserStatsToTrainingStats(userStats.value);
        } else {
          print('⚠️ Stats - Invalid stats data format: ${statsData.runtimeType}');
          // Don't create dummy data - just set to null so UI shows empty state
          userStats.value = null;
          trainingStats.value = null;
        }
      } catch (e) {
        print('⚠️ Stats - Failed to load user stats: $e');
        // Try legacy endpoint as fallback
        try {
          print('📊 Stats - Trying legacy training stats endpoint...');
          final legacyStatsData = await _dailyTrainingService.getTrainingStats();
          if (legacyStatsData is Map<String, dynamic>) {
            final dataToParse = legacyStatsData['data'] as Map<String, dynamic>? ?? legacyStatsData;
            trainingStats.value = TrainingStats.fromJson(dataToParse);
            userStats.value = _convertTrainingStatsToUserStats(trainingStats.value);
            _cachedStats.assignAll(dataToParse);
          } else {
            // No data from legacy endpoint either
            userStats.value = null;
            trainingStats.value = null;
          }
        } catch (legacyError) {
          print('⚠️ Stats - Legacy endpoint also failed: $legacyError');
          userStats.value = null;
          trainingStats.value = null;
        }
        
        // Use cached data if available, otherwise keep null (no dummy data)
        if (_cachedStats.isNotEmpty) {
          try {
            userStats.value = UserStats.fromJson(_cachedStats);
            trainingStats.value = _convertUserStatsToTrainingStats(userStats.value);
          } catch (parseError) {
            print('❌ Stats - Failed to parse cached stats: $parseError');
            // Don't create dummy data - keep null
            userStats.value = null;
            trainingStats.value = null;
          }
        }
        // If no cached data, keep null (no dummy data)
      }

      // Fetch recent daily plans
      // CRITICAL: Use getDailyTrainingPlans() instead of getDailyPlans() to get ALL plans including completed ones
      // getDailyPlans() filters out past completed plans, which prevents stats from showing completed workouts
      // getDailyTrainingPlans() returns all plans (completed and incomplete) which is what we need for stats
      // CRITICAL: Pass planType to ensure we only get plans of the active plan type
      try {
        print('📊 Stats - Fetching ALL daily plans (including completed) for planType: $planType...');
        final plansData = await _dailyTrainingService.getDailyTrainingPlans(planType: planType);
        print('📊 Stats - Daily plans result: ${plansData.length} items (filtered for $planType, includes completed plans)');
        
        // Store both parsed models and raw JSON data
        // Filter out any plans that might cause parsing errors
        final validPlans = <Map<String, dynamic>>[];
        for (final plan in plansData) {
          try {
            // Try to parse to validate the plan structure
            DailyTrainingPlan.fromJson(plan);
            validPlans.add(plan);
            
            // Log plan_type for debugging AI plan issues
            final planTypeValue = plan['plan_type']?.toString();
            final sourcePlanIdValue = plan['source_plan_id']?.toString();
            print('📊 Stats - Daily plan: id=${plan['id']}, plan_type=$planTypeValue, source_plan_id=$sourcePlanIdValue, is_completed=${plan['is_completed']}');
          } catch (e) {
            print('⚠️ Stats - Skipping invalid plan: $e');
            print('⚠️ Stats - Plan data: ${plan.keys.toList()}');
          }
        }
        dailyPlans.assignAll(validPlans.map((plan) => DailyTrainingPlan.fromJson(plan)));
        dailyPlansRaw.assignAll(validPlans);
        print('✅ Stats - Daily plans updated: ${dailyPlans.length} items');
        print('📊 Stats - Plan types in daily plans: ${validPlans.map((p) => p['plan_type']?.toString() ?? 'null').toSet().toList()}');
      } catch (e) {
        print('⚠️ Stats - Failed to load daily plans: $e');
        dailyPlans.clear();
        dailyPlansRaw.clear();
      }
      
      // Persist cached data
      await _persistCachedStats();
      
    } catch (e) {
      print('❌ Stats - Error loading data: $e');
    } finally {
      isLoading.value = false;
      hasLoadedOnce.value = true;
      print('🏁 Stats - Load completed');
    }
  }

  Future<void> refreshStats({bool forceSync = false}) async {
    print('🔄 Stats - Refreshing stats data...');
    await _loadLocalCompletions(); // Reload local completions first
    
    // Get active plan type to fetch/sync correct stats record
    final activePlanIds = _getActivePlanSourceIds();
    String? planType = activePlanIds?['planType'] as String?;
    
    // CRITICAL: Validate planType is set when there's an active plan
    if (activePlanIds != null && (planType == null || planType.isEmpty)) {
      print('⚠️ Stats - CRITICAL ERROR: Active plan found but planType is null or empty!');
      print('⚠️ Stats - Active plan IDs: $activePlanIds');
      print('⚠️ Stats - This will cause backend to sync stats for wrong plan type (likely web_assigned)');
      print('⚠️ Stats - Attempting to infer planType from active plan data...');
      
      // Try to infer planType from active plan
      if (Get.isRegistered<PlansController>()) {
        final plansController = Get.find<PlansController>();
        if (plansController.activePlan != null) {
          final plan = plansController.activePlan!;
          final planTypeFromField = plan['plan_type']?.toString().toLowerCase();
          if (planTypeFromField == 'ai_generated' || planTypeFromField == 'manual') {
            planType = planTypeFromField;
            print('✅ Stats - Inferred planType from active plan: $planType');
          } else {
            // Check AI indicators
            final isAiPlan = plan.containsKey('ai_generated') || 
                            plan.containsKey('gemini_generated') ||
                            plan.containsKey('ai_plan_id') ||
                            plan.containsKey('request_id') ||
                            (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
            planType = isAiPlan ? 'ai_generated' : 'manual';
            print('✅ Stats - Inferred planType from AI indicators: $planType');
          }
        }
      } else if (Get.isRegistered<SchedulesController>()) {
        planType = 'web_assigned';
        print('✅ Stats - Inferred planType as web_assigned (active schedule found)');
      }
    }
    
    if (planType != null && planType.isNotEmpty) {
      print('📊 Stats - Active plan type detected: $planType');
      print('📊 Stats - Will sync/fetch stats for plan type: $planType');
      print('📊 Stats - API call: POST /api/stats/mobile/sync with {planType: $planType}');
    } else {
      print('📊 Stats - No active plan detected - clearing stats data');
      // No active plan, clear all stats to show empty state
      userStats.value = null;
      trainingStats.value = null;
      dailyPlans.clear();
      dailyPlansRaw.clear();
      print('✅ Stats - Stats cleared (no active plan)');
      return;
    }
    
    if (forceSync) {
      // Use sync endpoint to force recalculation
      // Backend now creates separate stats records per plan type
      // CRITICAL: planType is guaranteed to be non-null at this point
      try {
        print('📊 Stats - Syncing stats (force recalculation) with planType=$planType...');
        final statsData = await _dailyTrainingService.syncStats(planType: planType!);
        if (statsData is Map<String, dynamic>) {
          final dataToParse = statsData['data'] as Map<String, dynamic>?;
          if (dataToParse != null) {
            userStats.value = UserStats.fromJson(dataToParse);
            trainingStats.value = _convertUserStatsToTrainingStats(userStats.value);
            _cachedStats.assignAll(dataToParse);
            await _persistCachedStats();
            print('✅ Stats - Stats synced successfully');
            print('📊 Stats - Daily workouts dates after sync: ${userStats.value?.dailyWorkouts.keys.toList()}');
            print('📊 Stats - Daily workouts data after sync: ${userStats.value?.dailyWorkouts}');
          } else {
            print('⚠️ Stats - Sync response has null data (no stats record exists yet for plan type: $planType)');
            print('⚠️ Stats - This is normal for new plans - stats will be created when workouts are completed');
            // Don't clear existing stats, just log the warning
          }
        } else {
          print('⚠️ Stats - Invalid sync response format');
          userStats.value = null;
          trainingStats.value = null;
        }
      } catch (e) {
        print('⚠️ Stats - Failed to sync stats: $e');
        // If sync fails, try to load stats from cache or use getStats endpoint
        // CRITICAL: planType is guaranteed to be non-null at this point
        try {
          print('📊 Stats - Attempting to load stats using getStats endpoint as fallback with planType=$planType...');
          final statsData = await _dailyTrainingService.getStats(refresh: true, planType: planType!);
          if (statsData is Map<String, dynamic>) {
            final dataToParse = statsData['data'] as Map<String, dynamic>? ?? statsData;
            userStats.value = UserStats.fromJson(dataToParse);
            trainingStats.value = _convertUserStatsToTrainingStats(userStats.value);
            _cachedStats.assignAll(dataToParse);
            await _persistCachedStats();
            print('✅ Stats - Stats loaded successfully using getStats endpoint');
          }
        } catch (fallbackError) {
          print('⚠️ Stats - Fallback getStats also failed: $fallbackError');
          // Don't create dummy data - just keep current state or null
        }
      }
    } else {
      // Use regular load with refresh flag
      // Backend now creates separate stats records per plan type
      // CRITICAL: planType is guaranteed to be non-null at this point
      try {
        print('📊 Stats - Loading stats with refresh flag and planType=$planType...');
        final statsData = await _dailyTrainingService.getStats(refresh: true, planType: planType!);
        if (statsData is Map<String, dynamic>) {
          final dataToParse = statsData['data'] as Map<String, dynamic>? ?? statsData;
          userStats.value = UserStats.fromJson(dataToParse);
          trainingStats.value = _convertUserStatsToTrainingStats(userStats.value);
          _cachedStats.assignAll(dataToParse);
          await _persistCachedStats();
        } else {
          print('⚠️ Stats - Invalid refresh response format');
          userStats.value = null;
          trainingStats.value = null;
        }
      } catch (e) {
        print('⚠️ Stats - Failed to refresh stats: $e');
        // Don't create dummy data - try to load from cache
    await loadStatsData();
      }
    }
    
    // Always reload daily plans after refreshing stats to ensure we have the latest completion status
    // Note: getDailyPlans() filters out past completed plans (is_stats_record: false filter)
    // So if a plan was completed on a different date than plan_date, it won't be returned
    // Stats sync should provide accurate counts for overall/weekly/monthly stats
    // 
    // Backend automatically syncs daily_plans from training_plan_assignments.daily_plans to daily_training_plans
    // when a plan is assigned. This ensures all daily plans are available in daily_training_plans for stats tracking.
    // CRITICAL: Use getDailyTrainingPlans() instead of getDailyPlans() to get ALL plans including completed ones
    // getDailyPlans() filters out past completed plans, which prevents stats from showing completed workouts
    // getDailyTrainingPlans() returns all plans (completed and incomplete) which is what we need for stats
    // CRITICAL: Pass planType to ensure we only get plans of the active plan type
    // Backend now defaults to web_assigned, but being explicit ensures proper isolation
    try {
      print('📊 Stats - Reloading ALL daily plans (including completed) after stats refresh for planType: $planType...');
      final plansData = await _dailyTrainingService.getDailyTrainingPlans(planType: planType);
      print('📊 Stats - Daily plans result: ${plansData.length} items (filtered for $planType, includes completed plans)');
      print('💡 Stats - Using getDailyTrainingPlans() to get ALL plans including completed ones for accurate stats');
      print('💡 Stats - Backend automatically syncs daily_plans from assignments, so all plans should be available');
      
      // Store both parsed models and raw JSON data
      // Filter out any plans that might cause parsing errors
      final validPlans = <Map<String, dynamic>>[];
      for (final plan in plansData) {
        try {
          // Try to parse to validate the plan structure
          DailyTrainingPlan.fromJson(plan);
          validPlans.add(plan);
        } catch (e) {
          print('⚠️ Stats - Skipping invalid plan: $e');
          print('⚠️ Stats - Plan data: ${plan.keys.toList()}');
        }
      }
      dailyPlans.assignAll(validPlans.map((plan) => DailyTrainingPlan.fromJson(plan)));
      dailyPlansRaw.assignAll(validPlans);
      print('✅ Stats - Daily plans updated: ${dailyPlans.length} items');
      print('📊 Stats - Sample plan data: ${validPlans.isNotEmpty ? validPlans.first : "No plans"}');
    } catch (e) {
      print('⚠️ Stats - Failed to reload daily plans: $e');
      // Don't clear existing data, just log the error
    }
  }

  Future<void> loadTodaysPlans() async {
    try {
      print('📊 Stats - Loading today\'s plans...');
      final todaysPlansData = await _dailyTrainingService.getTodaysPlans();
      print('📊 Stats - Today\'s plans result: ${todaysPlansData.length} items');
      
      // Update daily plans with today's data
      final todaysPlans = todaysPlansData.map((plan) => DailyTrainingPlan.fromJson(plan)).toList();
      
      // Merge with existing plans, avoiding duplicates
      final existingIds = dailyPlans.map((p) => p.id).toSet();
      final newPlans = todaysPlans.where((p) => !existingIds.contains(p.id)).toList();
      
      if (newPlans.isNotEmpty) {
        dailyPlans.addAll(newPlans);
        print('✅ Stats - Added ${newPlans.length} new daily plans');
      }

      // Bring most-recent today plan(s) to the top
      dailyPlans.sort((a, b) => b.planDate.compareTo(a.planDate));
    } catch (e) {
      print('⚠️ Stats - Failed to load today\'s plans: $e');
    }
  }

  // Get completed workouts count for today (only show completed workouts count of today)
  // Count individual workouts completed today (not days)
  // Uses dailyPlansRaw from getDailyPlans() which now returns completed plans correctly
  int getTodaysCompletedWorkouts() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for today\'s workouts');
      return 0;
    }
    
    // Get today's date in local timezone (YYYY-MM-DD)
    final now = DateTime.now();
    final today = now.toIso8601String().split('T').first;
    
    // Also get today in UTC to handle timezone differences
    final todayUtc = DateTime.utc(now.year, now.month, now.day).toIso8601String().split('T').first;
    
    // Count individual completed workouts for today (not days)
    int totalWorkouts = 0;
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for today\'s workouts');
      return 0;
    }
    
    // Check filtered dailyPlansRaw first (more reliable source from API)
    print('📊 Stats - Checking ${filteredPlans.length} filtered plans for today\'s workouts');
    for (final planRaw in filteredPlans) {
      final planDate = planRaw['plan_date'] as String? ?? '';
      final completedAt = planRaw['completed_at'] as String?;
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      final planId = planRaw['id'] ?? 'N/A';
      
      // Check both plan_date and completed_at for today (handle timezone differences)
      final planDateStr = planDate.split('T').first;
      final completedAtStr = completedAt != null ? completedAt.split('T').first : null;
      
      // IMPORTANT: Use completed_at date if available (when plan was actually completed)
      // Otherwise use plan_date (when plan was scheduled)
      // This prevents double-counting if both dates match today
      String? dateToCheck;
      if (completedAtStr != null && (completedAtStr == today || completedAtStr == todayUtc)) {
        // Plan was completed today, use completed_at date
        dateToCheck = completedAtStr;
        print('📊 Stats - Plan $planId: Using completed_at date ($completedAtStr) for today\'s count');
      } else if (planDateStr == today || planDateStr == todayUtc) {
        // Plan is scheduled for today, use plan_date
        dateToCheck = planDateStr;
        print('📊 Stats - Plan $planId: Using plan_date ($planDateStr) for today\'s count');
      } else {
        print('📊 Stats - Plan $planId: Not for today (plan_date=$planDateStr, completed_at=$completedAtStr, today=$today)');
      }
      
      // Only count if the plan is for today (using the appropriate date)
      if (dateToCheck != null) {
        // Count individual workouts that are completed (even if plan is not fully completed)
        dynamic exercisesDetails = planRaw['exercises_details'];
        List<Map<String, dynamic>> exercises = [];
        
        // Handle new structure: { workouts: [...], snapshots: [...] }
        if (exercisesDetails is List) {
          exercises = exercisesDetails.cast<Map<String, dynamic>>();
        } else if (exercisesDetails is Map<String, dynamic>) {
          if (exercisesDetails['workouts'] is List) {
            exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['exercises'] is List) {
            exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['items'] is List) {
            exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
          }
        } else if (exercisesDetails is String) {
          try {
            final parsed = jsonDecode(exercisesDetails);
            if (parsed is List) {
              exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            } else if (parsed is Map<String, dynamic>) {
              if (parsed['workouts'] is List) {
                exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['exercises'] is List) {
                exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['items'] is List) {
                exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
              }
            }
          } catch (e) {
            print('⚠️ Stats - Failed to parse exercises_details in getTodaysCompletedWorkouts: $e');
          }
        }
        
        // Count workouts that are completed (ONLY count completed workouts)
        // Only count workouts that are explicitly marked as completed
        print('📊 Stats - Plan $planId: Found ${exercises.length} exercises in exercises_details');
        int workoutsInThisPlan = 0;
        for (final exercise in exercises) {
          if (exercise is Map<String, dynamic>) {
            final isWorkoutCompleted = exercise['is_completed'] as bool? ?? false;
            final workoutName = exercise['workout_name'] ?? exercise['name'] ?? 'Unknown';
            // Only count if:
            // 1. Workout is explicitly marked as completed (is_completed = true), OR
            // 2. Plan is fully completed (all workouts in a completed plan are considered completed)
            // DO NOT count workouts without is_completed flag unless plan is completed
            if (isCompleted) {
              // If plan is completed, count all workouts (plan completion means all workouts done)
              totalWorkouts++;
              workoutsInThisPlan++;
              print('📊 Stats - Plan $planId: Counting workout "$workoutName" (plan completed)');
            } else if (isWorkoutCompleted) {
              // If plan is not completed, only count workouts explicitly marked as completed
              totalWorkouts++;
              workoutsInThisPlan++;
              print('📊 Stats - Plan $planId: Counting workout "$workoutName" (explicitly completed)');
            } else {
              print('📊 Stats - Plan $planId: Skipping workout "$workoutName" (not completed)');
            }
          }
        }
        print('📊 Stats - Plan $planId: Contributed $workoutsInThisPlan workouts to today\'s total (total so far: $totalWorkouts)');
      }
    }
    
    // Also check parsed dailyPlans (fallback) - but only if they match the active plan
    // Note: dailyPlans is parsed from dailyPlansRaw, so we should use filteredPlans instead
    // This fallback is kept for backward compatibility but should rarely be needed
    // Since we already have filteredPlans, we can skip this to avoid double-counting
    // REMOVED: Parsed dailyPlans fallback to avoid counting unfiltered plans
    
    // Also count locally stored completions for today (each completion is a workout)
    // IMPORTANT: Filter local completions by active plan to avoid counting other plans
    final localCompletions = _getLocalCompletionsForDate(today);
    final planId = activePlanIds['planId'] as int?;
    final assignmentId = activePlanIds['assignmentId'] as int?;
    final planType = activePlanIds['planType'] as String?;
    final filteredLocalCompletions = localCompletions.where((completion) {
      final completionPlanId = completion['plan_id'] as int?;
      // Match by plan_id (for manual/AI plans) or assignment_id (for assigned plans)
      if (planType == 'manual' || planType == 'ai_generated') {
        return completionPlanId == planId;
      } else if (planType == 'web_assigned') {
        return completionPlanId == planId || completion['assignment_id'] == assignmentId;
      }
      return false;
    }).toList();
    // IMPORTANT: Only count local completions if they're NOT already in the database
    // Local completions are only for workouts that failed to submit to the API
    // If a workout is in the database (filteredPlans), it's already counted above
    // So we should NOT double-count by adding local completions
    // REMOVED: Local completions counting to avoid double-counting
    // Local completions are only a fallback when API submission fails
    // If workouts are in the database, they're already counted from filteredPlans
    print('📊 Stats - Total workouts counted from database: $totalWorkouts');
    print('📊 Stats - Skipping local completions to avoid double-counting (workouts already in database)');
    
    // PRIORITY: Use UserStats from backend as primary source (backend calculates correctly)
    // Backend now creates separate stats records per plan type, so UserStats is filtered correctly
    if (userStats.value != null && filteredPlans.isNotEmpty) {
      // Backend groups daily workouts by completed_at date when completed today
      // Structure: {"2025-11-06": {"workouts": ["Chest", "Back"], "count": 2}}
      // After parsing: {"2025-11-06": ["Chest", "Back"]}
      
      // Check today's date in dailyWorkouts (backend's source of truth)
      // dailyWorkouts is Map<String, List<String>>, so values are always List<String>
      final todayWorkouts = userStats.value!.dailyWorkouts[today] ?? userStats.value!.dailyWorkouts[todayUtc];
      if (todayWorkouts != null && todayWorkouts.isNotEmpty) {
        // dailyWorkouts values are already parsed as List<String> by UserStats.fromJson
        final todayCount = todayWorkouts.length;
        print('📊 Stats - Using UserStats today count: $todayCount (from dailyWorkouts list)');
        
        if (todayCount > 0) {
          print('✅ Stats - Using UserStats backend count for today: $todayCount (database calculation: $totalWorkouts)');
          return todayCount;
        }
      }
      
      // Also check taskCompletionReport.today.totalWorkouts as fallback
      final todayTotalWorkouts = userStats.value!.taskCompletionReport.today.totalWorkouts;
      if (todayTotalWorkouts != null && todayTotalWorkouts > 0 && totalWorkouts == 0) {
        print('✅ Stats - Using UserStats taskCompletionReport.today.totalWorkouts: $todayTotalWorkouts');
        return todayTotalWorkouts;
      }
    }
    
    // Fallback to database calculation if UserStats not available
    if (false && totalWorkouts == 0 && userStats.value != null && filteredPlans.isNotEmpty) {
      // Backend now groups daily workouts by completed_at date when completed today
      // If a plan is completed today, it uses today's date instead of plan_date
      // This ensures today's workouts are grouped under today's date in dailyWorkouts
      // Structure: {"2025-11-06": {"workouts": ["Chest", "Back"], "count": 2}}
      // After parsing: {"2025-11-06": ["Chest", "Back"]}
      
      // Log all available dates in dailyWorkouts for debugging
      print('📊 Stats - Checking dailyWorkouts for today\'s workouts');
      print('📊 Stats - Today date (local): $today');
      print('📊 Stats - Today date (UTC): $todayUtc');
      print('📊 Stats - Available dates in dailyWorkouts: ${userStats.value!.dailyWorkouts.keys.toList()}');
      
      // First, try to get count from dailyWorkouts map using today's date
      // Backend now uses completed_at date when grouping (if completed today, uses today's date)
      final todayWorkouts = userStats.value!.dailyWorkouts[today];
      if (todayWorkouts != null && todayWorkouts.isNotEmpty) {
        print('✅ Stats - Found today\'s workouts in dailyWorkouts[$today]: ${todayWorkouts.length} workouts');
        print('📊 Stats - Workout names: ${todayWorkouts.join(", ")}');
        print('💡 Stats - Backend correctly grouped workouts by completed_at date (today)');
        return todayWorkouts.length;
      }
      
      // Also check UTC date format
      final todayWorkoutsUtc = userStats.value!.dailyWorkouts[todayUtc];
      if (todayWorkoutsUtc != null && todayWorkoutsUtc.isNotEmpty) {
        print('✅ Stats - Found today\'s workouts in dailyWorkouts[$todayUtc]: ${todayWorkoutsUtc.length} workouts');
        print('📊 Stats - Workout names: ${todayWorkoutsUtc.join(", ")}');
        print('💡 Stats - Backend correctly grouped workouts by completed_at date (today UTC)');
        return todayWorkoutsUtc.length;
      }
      
      // Second, try taskCompletionReport.today.totalWorkouts (backend calculated count)
      final todayStats = userStats.value!.taskCompletionReport.today;
      if (todayStats.totalWorkouts != null && todayStats.totalWorkouts! > 0) {
        print('✅ Stats - Today\'s completed workouts (from UserStats taskCompletionReport.today.totalWorkouts): ${todayStats.totalWorkouts}');
        return todayStats.totalWorkouts!;
      }
      
      // If still 0, check if there's data for yesterday or recent dates (might be a timezone/date issue)
      // Also check all available dates to see if there's a pattern
      final allDates = userStats.value!.dailyWorkouts.keys.toList();
      if (allDates.isNotEmpty) {
        print('📊 Stats - Checking all available dates in dailyWorkouts for potential matches:');
        for (final date in allDates) {
          final workouts = userStats.value!.dailyWorkouts[date];
          print('📊 Stats - Date: $date, Workouts count: ${workouts?.length ?? 0}, Workouts: ${workouts?.join(", ") ?? "N/A"}');
        }
        
        // WORKAROUND: Backend is grouping by plan_date instead of completed_at
        // Check if there's data for yesterday and if any plans were completed today
        final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T').first;
        final yesterdayWorkouts = userStats.value!.dailyWorkouts[yesterday];
        if (yesterdayWorkouts != null && yesterdayWorkouts.isNotEmpty) {
          print('💡 Stats - Found workouts for yesterday ($yesterday): ${yesterdayWorkouts.length} workouts');
          
          // Check if any plans were completed today (based on completed_at)
          bool hasTodayCompleted = false;
          for (final planRaw in dailyPlansRaw) {
            final completedAt = planRaw['completed_at'] as String?;
            if (completedAt != null) {
              final completedAtStr = completedAt.split('T').first;
              if (completedAtStr == today || completedAtStr == todayUtc) {
                hasTodayCompleted = true;
                print('💡 Stats - Found plan completed today: plan_date=${planRaw['plan_date']}, completed_at=$completedAt');
                break;
              }
            }
          }
          
          // If we have plans completed today but grouped under yesterday, use yesterday's count as workaround
          // This handles the case where backend hasn't updated to use completed_at for grouping yet
          if (hasTodayCompleted) {
            print('💡 Stats - Using yesterday\'s workouts as workaround (backend grouped by plan_date instead of completed_at)');
            print('💡 Stats - Returning ${yesterdayWorkouts.length} workouts from yesterday\'s date');
            return yesterdayWorkouts.length;
          }
        }
        
        // Also check if the most recent date is within 1 day (another workaround)
        allDates.sort();
        if (allDates.isNotEmpty) {
          final mostRecentDate = allDates.last;
          final mostRecentWorkouts = userStats.value!.dailyWorkouts[mostRecentDate];
          if (mostRecentWorkouts != null && mostRecentWorkouts.isNotEmpty) {
            final mostRecentDateObj = DateTime.tryParse(mostRecentDate);
            if (mostRecentDateObj != null) {
              // Normalize both dates to midnight for accurate comparison
              final todayMidnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              final mostRecentMidnight = DateTime(mostRecentDateObj.year, mostRecentDateObj.month, mostRecentDateObj.day);
              final daysDiff = todayMidnight.difference(mostRecentMidnight).inDays.abs();
              
              // WORKAROUND: If most recent date is within 1 day (today or yesterday), use it
              // This handles the case where backend groups by plan_date instead of completed_at
              // The backend should use completed_at date, but until it's fixed, use most recent date
              if (daysDiff <= 1) {
                // Check if stats were synced today (indicates recent activity)
                final statsDateUpdated = userStats.value!.dateUpdated;
                final statsDateStr = statsDateUpdated.toIso8601String().split('T').first;
                final statsDateMatches = statsDateStr == today || statsDateStr == todayUtc;
                
                // Check if any plans were completed today (from dailyPlansRaw if available)
                bool hasTodayCompleted = false;
                if (dailyPlansRaw.isNotEmpty) {
                  for (final planRaw in dailyPlansRaw) {
                    final completedAt = planRaw['completed_at'] as String?;
                    if (completedAt != null) {
                      final completedAtStr = completedAt.split('T').first;
                      if (completedAtStr == today || completedAtStr == todayUtc) {
                        hasTodayCompleted = true;
                        print('💡 Stats - Found plan completed today: plan_date=${planRaw['plan_date']}, completed_at=$completedAt');
                        break;
                      }
                    }
                  }
                }
                
                // Use most recent date if:
                // 1. Stats were synced today (recent activity), OR
                // 2. We have plans completed today (confirmed), OR
                // 3. dailyPlansRaw is empty (can't verify, but most recent date is within 1 day)
                if (statsDateMatches || hasTodayCompleted || dailyPlansRaw.isEmpty) {
                  print('💡 Stats - Most recent date ($mostRecentDate) is within 1 day, using as workaround for today\'s count');
                  print('💡 Stats - Backend grouped by plan_date instead of completed_at, or timezone mismatch');
                  print('💡 Stats - Stats synced: $statsDateMatches, Plans completed today: $hasTodayCompleted');
                  print('💡 Stats - Returning ${mostRecentWorkouts.length} workouts from most recent date');
                  return mostRecentWorkouts.length;
                }
              }
            }
          }
        }
      }
      
      // Log detailed warning
      print('⚠️ Stats - Today\'s workouts not found in dailyWorkouts');
      print('⚠️ Stats - Looking for dates: $today (local) or $todayUtc (UTC)');
      print('⚠️ Stats - Available dates: ${userStats.value!.dailyWorkouts.keys.toList()}');
      print('⚠️ Stats - taskCompletionReport.today.totalWorkouts: ${todayStats.totalWorkouts}');
      print('⚠️ Stats - taskCompletionReport.today.completed: ${todayStats.completed}');
      if (dailyPlansRaw.isEmpty) {
        print('⚠️ Stats - getDailyPlans() also returned empty');
      }
    }
    
    if (totalWorkouts > 0) {
      print('📊 Stats - Today\'s completed workouts (individual count from dailyPlansRaw): $totalWorkouts');
    } else {
      print('📊 Stats - Today\'s completed workouts (individual count): $totalWorkouts');
    }
    return totalWorkouts;
  }

  // Load local completions from storage
  Future<void> _loadLocalCompletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'local_workout_completions_user_$userId';
      
      final existingJson = prefs.getString(key) ?? '[]';
      final List<dynamic> completions = jsonDecode(existingJson);
      _localCompletions.assignAll(completions.cast<Map<String, dynamic>>());
      
      print('📊 Stats - Loaded ${_localCompletions.length} local completions');
    } catch (e) {
      print('❌ Stats - Error loading local completions: $e');
    }
  }

  // Clear all stats data when there are no assigned plans
  // This should be called when all plans are unassigned
  Future<void> clearAllStatsData() async {
    try {
      print('🧹 Stats - Clearing all stats data (no assigned plans)...');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      
      // 1. Clear all daily plans from memory
      dailyPlans.clear();
      dailyPlansRaw.clear();
      print('🧹 Stats - Cleared all daily plans from memory');
      
      // 2. Clear all local completions
      _localCompletions.clear();
      final key = 'local_workout_completions_user_$userId';
      await prefs.remove(key);
      print('🧹 Stats - Cleared all local completions from storage');
      
      // 3. Clear cached stats
      _cachedStats.clear();
      _cachedRecentWorkouts.clear();
      await prefs.remove('cached_training_stats_user_$userId');
      await prefs.remove('cached_recent_workouts_user_$userId');
      print('🧹 Stats - Cleared all cached stats from local storage');
      
      // 4. Reset userStats to null (will show empty state)
      userStats.value = null;
      trainingStats.value = null;
      
      // 5. Force refresh stats to sync with backend (backend should have deleted all data)
      print('🔄 Stats - Refreshing stats after clearing all data...');
      await refreshStats(forceSync: true);
      
      print('✅ Stats - All stats data cleared');
    } catch (e) {
      print('❌ Stats - Error clearing all stats data: $e');
    }
  }

  // Get the currently active plan's source IDs for filtering stats
  // Returns a map with planId, assignmentId, webPlanId, approvalId, and planType
  // PRIORITIZES PlansController (manual/AI plans) over SchedulesController (assigned plans)
  Map<String, dynamic>? _getActivePlanSourceIds() {
    try {
      // PRIORITY 1: Check PlansController for active manual/AI plan FIRST
      // (Manual/AI plans take precedence when started)
      if (Get.isRegistered<PlansController>()) {
        final plansController = Get.find<PlansController>();
        if (plansController.activePlan != null) {
          final plan = plansController.activePlan!;
          final planId = int.tryParse(plan['id']?.toString() ?? '');
          
          if (planId != null) {
            // CRITICAL: Check plan_type field first (most reliable indicator)
            // Backend may set plan_type='ai_generated' or plan_type='manual' directly
            String? planTypeFromField = plan['plan_type']?.toString().toLowerCase();
            if (planTypeFromField == 'ai_generated' || planTypeFromField == 'manual') {
              print('🔍 Stats - Found plan_type field in plan data: $planTypeFromField');
            }
            
            // Determine if it's AI or Manual
            // Priority: 1) plan_type field, 2) AI indicators, 3) default to manual
            final isAiPlan = planTypeFromField == 'ai_generated' ||
                            plan.containsKey('ai_generated') || 
                            plan.containsKey('gemini_generated') ||
                            plan.containsKey('ai_plan_id') ||
                            plan.containsKey('request_id') ||
                            (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
            
            // Use plan_type field if available, otherwise infer from indicators
            final planType = planTypeFromField == 'ai_generated' || planTypeFromField == 'manual' 
                ? planTypeFromField! 
                : (isAiPlan ? 'ai_generated' : 'manual');
            
            print('🔍 Stats - Active plan detected: planId=$planId, isAiPlan=$isAiPlan, planType=$planType');
            print('🔍 Stats - Plan keys: ${plan.keys.toList()}');
            print('🔍 Stats - plan_type field: $planTypeFromField');
            print('🔍 Stats - AI indicators: ai_generated=${plan.containsKey('ai_generated')}, gemini_generated=${plan.containsKey('gemini_generated')}, ai_plan_id=${plan.containsKey('ai_plan_id')}, request_id=${plan.containsKey('request_id')}');
            
            // For manual/AI plans, source_plan_id in daily_training_plans is the approval_id, not plan_id
            // Get the approval_id from the plan or from the controller's map
            int? approvalId = int.tryParse(plan['approval_id']?.toString() ?? '');
            if (approvalId == null) {
              approvalId = plansController.getApprovalIdForPlan(planId);
              
              // If still null, check if plan data has approval_id field (even if null)
              // This handles cases where backend includes approval_id key but value is null
              if (approvalId == null && plan.containsKey('approval_id')) {
                final approvalIdFromData = plan['approval_id'];
                if (approvalIdFromData != null) {
                  approvalId = int.tryParse(approvalIdFromData.toString());
                }
              }
            }
            return {
              'planId': planId,
              'approvalId': approvalId, // This is the source_plan_id in daily_training_plans
              'assignmentId': null,
              'webPlanId': null,
              'planType': planType,
            };
          }
        }
      }
      
      // PRIORITY 2: Check SchedulesController for active assigned plan
      // (Only if no manual/AI plan is active)
      if (Get.isRegistered<SchedulesController>()) {
        final schedulesController = Get.find<SchedulesController>();
        if (schedulesController.activeSchedule != null) {
          final schedule = schedulesController.activeSchedule!;
          final scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
          final webPlanId = schedule['web_plan_id'] as int?;
          final assignmentId = schedule['assignment_id'] as int?;
          
          print('🔍 Stats - Found active assigned plan: scheduleId=$scheduleId, assignmentId=$assignmentId, webPlanId=$webPlanId');
          print('🔍 Stats - Active schedule keys: ${schedule.keys.toList()}');
          
          if (scheduleId != null) {
            return {
              'planId': scheduleId,
              'assignmentId': assignmentId ?? scheduleId,
              'webPlanId': webPlanId,
              'approvalId': null,
              'planType': 'web_assigned',
            };
          } else {
            print('⚠️ Stats - Active schedule found but scheduleId is null');
          }
        } else {
          print('🔍 Stats - SchedulesController registered but no activeSchedule');
        }
      } else {
        print('🔍 Stats - SchedulesController not registered');
      }
      
      print('🔍 Stats - No active plan found');
      return null;
    } catch (e) {
      print('⚠️ Stats - Error getting active plan source IDs: $e');
      return null;
    }
  }

  // Filter dailyPlansRaw to only include plans from the active plan
  List<Map<String, dynamic>> _filterPlansByActivePlan(List<Map<String, dynamic>> plans) {
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      // No active plan, return empty list (no stats should show)
      print('🔍 Stats - No active plan, filtering out all plans');
      return [];
    }
    
    final planId = activePlanIds['planId'] as int?;
    final approvalId = activePlanIds['approvalId'] as int?;
    final assignmentId = activePlanIds['assignmentId'] as int?;
    final webPlanId = activePlanIds['webPlanId'] as int?;
    final planType = activePlanIds['planType'] as String?;
    
    print('🔍 Stats - Filtering plans with: planId=$planId, assignmentId=$assignmentId, webPlanId=$webPlanId, planType=$planType');
    
    final filtered = plans.where((planRaw) {
      final sourcePlanId = planRaw['source_plan_id'] as int?;
      final sourceAssignmentId = planRaw['source_assignment_id'] as int?;
      final planAssignmentId = planRaw['assignment_id'] as int?;
      String? planTypeRaw = planRaw['plan_type'] as String?;

      // Some records (especially older synced ones) may have null/empty plan_type.
      // Infer the most likely plan type based on identifying fields so we don't drop valid plans.
      // IMPORTANT: Also consider the active plan's plan type when inferring to avoid mismatches
      if (planTypeRaw == null || planTypeRaw.isEmpty) {
        final sourcePlanType = planRaw['source_plan_type']?.toString();
        print('🔍 Stats - Plan has null/empty plan_type, inferring from fields. sourcePlanType=$sourcePlanType, planRaw keys: ${planRaw.keys.toList()}');
        print('🔍 Stats - Active plan type: $planType (will use this as fallback if inference fails)');
        
        if (planRaw.containsKey('assignment_id') ||
            planRaw.containsKey('source_assignment_id') ||
            sourcePlanType == 'web_assigned') {
          planTypeRaw = 'web_assigned';
          print('🔍 Stats - Inferred plan_type as web_assigned');
        } else if (sourcePlanType == 'ai_generated') {
          planTypeRaw = 'ai_generated';
          print('🔍 Stats - Inferred plan_type as ai_generated (from source_plan_type)');
        } else if (planType == 'ai_generated' && (planId != null && sourcePlanId == planId || approvalId != null && sourcePlanId == approvalId)) {
          // PRIORITY: If active plan is AI and IDs match, infer as ai_generated FIRST (before checking approval_id)
          planTypeRaw = 'ai_generated';
          print('🔍 Stats - Inferred plan_type as ai_generated (active plan is AI, and IDs match)');
        } else if (planRaw.containsKey('approval_id') ||
                   planRaw.containsKey('source_approval_id') ||
                   sourcePlanType == 'manual') {
          // For plans with approval_id, check if active plan is AI to avoid misclassification
          if (planType == 'ai_generated' && (planId != null && sourcePlanId == planId || approvalId != null && sourcePlanId == approvalId)) {
            planTypeRaw = 'ai_generated';
            print('🔍 Stats - Inferred plan_type as ai_generated (active plan is AI, and IDs match)');
          } else {
            planTypeRaw = 'manual';
            print('🔍 Stats - Inferred plan_type as manual');
          }
        } else if (planType != null && planType.isNotEmpty) {
          // Fallback: Use active plan's type if IDs match (for AI plans especially)
          if (planId != null && sourcePlanId == planId || approvalId != null && sourcePlanId == approvalId) {
            planTypeRaw = planType;
            print('🔍 Stats - Inferred plan_type as $planType (from active plan type, IDs match)');
          } else {
            print('⚠️ Stats - Could not infer plan_type for plan id=${planRaw['id']}, sourcePlanId=$sourcePlanId (IDs don\'t match active plan)');
          }
        } else {
          // If we can't infer, log it for debugging
          print('⚠️ Stats - Could not infer plan_type for plan id=${planRaw['id']}, sourcePlanId=$sourcePlanId');
        }
      }
      
      // CRITICAL: Match by plan type first - MUST match exactly
      // This ensures assigned plans and manual/AI plans are completely isolated
      // Manual plans (plan_type='manual') and assigned plans (plan_type='web_assigned') should never interfere
      if (planTypeRaw != planType) {
        return false; // Reject any plans with different plan type immediately
      }
      
      // For assigned plans, match by assignment_id or source_assignment_id
      // IMPORTANT: For assigned plans, source_plan_id in daily_training_plans is the assignment_id
      // So we need to match source_plan_id with assignmentId (or planId if assignmentId is null)
      if (planType == 'web_assigned') {
        bool matches = false;
        
        // For assigned plans, the scheduleId IS the assignment_id
        // So we should match source_plan_id with planId (which is the scheduleId/assignmentId)
        if (planId != null) {
          // Primary match: source_plan_id should equal planId (which is the assignment ID)
          matches = sourcePlanId == planId || 
                   sourceAssignmentId == planId ||
                   planAssignmentId == planId;
        }
        
        // Also check assignmentId if it's different from planId
        if (!matches && assignmentId != null && assignmentId != planId) {
          matches = sourcePlanId == assignmentId || 
                   sourceAssignmentId == assignmentId || 
                   planAssignmentId == assignmentId;
        }
        
        // Fallback: match by web_plan_id
        if (!matches && webPlanId != null) {
          matches = sourcePlanId == webPlanId;
        }
        
        if (matches) {
          // ADDITIONAL FILTER: Check if plan was created after assignment (to avoid old plans)
          // Get assignment details to check creation timestamp
          try {
            if (Get.isRegistered<SchedulesController>()) {
              final schedulesController = Get.find<SchedulesController>();
              final activeSchedule = schedulesController.activeSchedule;
              if (activeSchedule != null) {
                final assignmentCreatedAt = activeSchedule['created_at'] as String?;
                final assignmentUpdatedAt = activeSchedule['updated_at'] as String?;
                final planCreatedAt = planRaw['created_at'] as String?;
                
                if (assignmentCreatedAt != null || assignmentUpdatedAt != null) {
                  final assignmentTimestamp = assignmentUpdatedAt != null 
                      ? DateTime.tryParse(assignmentUpdatedAt)
                      : (assignmentCreatedAt != null ? DateTime.tryParse(assignmentCreatedAt) : null);
                  
                  if (assignmentTimestamp != null && planCreatedAt != null) {
                    final planCreated = DateTime.tryParse(planCreatedAt);
                    if (planCreated != null && planCreated.isBefore(assignmentTimestamp)) {
                      print('🔍 Stats - ⚠️ Filtering out old plan: id=${planRaw['id']}, plan_created=$planCreatedAt is before assignment timestamp=$assignmentTimestamp');
                      return false;
                    }
                  }
                }
              }
            }
          } catch (e) {
            print('⚠️ Stats - Error checking assignment timestamp: $e');
            // Continue with match if timestamp check fails
          }
          
          print('✅ Stats - Matched assigned plan: sourcePlanId=$sourcePlanId matches planId=$planId');
        } else {
          print('🔍 Stats - Assigned plan mismatch: planId=$planId, assignmentId=$assignmentId, webPlanId=$webPlanId');
          print('🔍 Stats - Plan data: sourcePlanId=$sourcePlanId, sourceAssignmentId=$sourceAssignmentId, planAssignmentId=$planAssignmentId, planType=$planTypeRaw');
        }
        
        return matches;
      }
      
      // For manual/AI plans, source_plan_id can be either approval_id OR plan_id
      // - If plan has approval_id: source_plan_id = approval_id
      // - If plan has no approval_id: source_plan_id = plan_id (direct match)
      if (planType == 'manual' || planType == 'ai_generated') {
        bool matches = false;
        
        if (approvalId != null) {
          // Primary match: source_plan_id should equal approval_id
          matches = sourcePlanId == approvalId;
          if (matches) {
            print('✅ Stats - Matched ${planType} plan by approval_id: sourcePlanId=$sourcePlanId == approvalId=$approvalId');
          }
        }
        
        // Fallback: If approval_id is null or doesn't match, try matching by plan_id
        // IMPORTANT: Match ALL plans by plan_id (not just completed ones)
        // This is because when approval_id is null, source_plan_id = plan_id for all plans
        if (!matches && planId != null && sourcePlanId == planId) {
          matches = true;
          print('✅ Stats - Matched ${planType} plan by plan_id: sourcePlanId=$sourcePlanId == planId=$planId (approvalId is null)');
        }
        
        if (!matches) {
          print('🔍 Stats - ${planType} plan mismatch: planId=$planId, approvalId=$approvalId, sourcePlanId=$sourcePlanId, planTypeRaw=$planTypeRaw');
        }
        
        return matches;
      }
      
      return false;
    }).toList();
    
    print('🔍 Stats - Filtered ${plans.length} plans to ${filtered.length} plans for active plan (ID: $planId, approvalId: $approvalId, type: $planType)');
    return filtered;
  }

  // Clean up stats data for a deleted/unassigned plan
  // This removes daily plans, local completions, and cached stats related to the plan
  // [deleteFromDatabase] - If true, also deletes daily training plans from the database (for unassigned/deleted plans)
  // If false, only clears local data (for stopped plans that might be resumed)
  Future<void> cleanupStatsForPlan(int planId, {int? assignmentId, int? webPlanId, bool deleteFromDatabase = false}) async {
    try {
      print('🧹 Stats - Cleaning up stats data for plan ID: $planId');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      
      // 1. Remove daily plans from memory that are related to this plan
      // DailyTrainingPlan model doesn't store source IDs, so we check raw JSON data
      int removedPlans = 0;
      final idsToRemove = <int>{};
      
      dailyPlansRaw.removeWhere((planRaw) {
        final sourcePlanId = planRaw['source_plan_id'] as int?;
        final sourceAssignmentId = planRaw['source_assignment_id'] as int?;
        final planAssignmentId = planRaw['assignment_id'] as int?;
        final dailyPlanId = planRaw['id'] as int?;
        
        final matches = sourcePlanId == planId || 
               sourceAssignmentId == planId || 
               planAssignmentId == planId ||
               (assignmentId != null && (sourceAssignmentId == assignmentId || planAssignmentId == assignmentId)) ||
               (webPlanId != null && sourcePlanId == webPlanId);
        
        if (matches && dailyPlanId != null) {
          idsToRemove.add(dailyPlanId);
          removedPlans++;
          return true;
        }
        return false;
      });
      
      // Also remove from dailyPlans model list by matching IDs
      dailyPlans.removeWhere((plan) => idsToRemove.contains(plan.id));
      
      print('🧹 Stats - Removed $removedPlans daily plans from memory for plan $planId');
      
      // 2. Remove local completions related to this plan
      int removedCompletions = 0;
      _localCompletions.removeWhere((completion) {
        final completionPlanId = completion['plan_id'] as int?;
        final completionAssignmentId = completion['assignment_id'] as int?;
        
        final matches = completionPlanId == planId ||
                       completionAssignmentId == planId ||
                       (assignmentId != null && completionAssignmentId == assignmentId);
        
        if (matches) {
          removedCompletions++;
          return true;
        }
        return false;
      });
      
      // Persist updated local completions
      if (removedCompletions > 0) {
        final key = 'local_workout_completions_user_$userId';
        await prefs.setString(key, jsonEncode(_localCompletions));
        print('🧹 Stats - Removed $removedCompletions local completions from storage for plan $planId');
      }
      
      // 3. Delete daily training plans from database (only if deleteFromDatabase is true)
      // This ensures that when a plan is deleted from the web portal, all associated daily_training_plans are also deleted
      // We don't delete from database when just stopping a plan (user might resume it later)
      if (deleteFromDatabase) {
        try {
          print('🗑️ Stats - Deleting daily training plans from database for plan $planId...');
          await _dailyTrainingService.deleteDailyPlansBySource(
            assignmentId: assignmentId ?? planId, // For assigned plans, use assignmentId or planId
            sourcePlanId: planId, // Also try sourcePlanId as fallback
          );
          print('✅ Stats - Daily training plans deleted from database for plan $planId');
        } catch (e) {
          print('⚠️ Stats - Error deleting daily training plans from database: $e');
          // Continue with cleanup even if database deletion fails
        }
      } else {
        print('ℹ️ Stats - Skipping database deletion (plan stopped, not deleted - user might resume)');
      }
      
      // 4. Clear cached stats (they may contain data from the deleted plan)
      // The cached stats will be regenerated when we refresh
      _cachedStats.clear();
      _cachedRecentWorkouts.clear();
      await prefs.remove('cached_training_stats_user_$userId');
      await prefs.remove('cached_recent_workouts_user_$userId');
      print('🧹 Stats - Cleared cached stats from local storage for plan $planId');
      
      // 5. Reset userStats to show zero values immediately (don't refresh from backend)
      // This ensures the UI shows cleared stats immediately when plan is stopped
      // We don't refresh from backend because backend still has the data
      // The stats will be refreshed when a plan is started again
      userStats.value = null;
      trainingStats.value = null;
      
      // Create default zero stats to show in UI immediately
      userStats.value = _createDefaultUserStats();
      print('🧹 Stats - Reset userStats to zero values for immediate UI update');
      print('🧹 Stats - Stats will remain zero until a plan is started again');
      
      print('✅ Stats - Cleanup completed for plan $planId');
    } catch (e) {
      print('❌ Stats - Error cleaning up stats for plan $planId: $e');
    }
  }

  // Get local workout completions for a specific date
  List<Map<String, dynamic>> _getLocalCompletionsForDate(String date) {
    return _localCompletions.where((completion) {
      final completionDate = completion['date'] as String?;
      return completionDate == date;
    }).toList();
  }

  // Get local workout completions (async version)
  Future<List<Map<String, dynamic>>> _getLocalCompletionsForDateAsync(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'local_workout_completions_user_$userId';
      
      final existingJson = prefs.getString(key) ?? '[]';
      final List<dynamic> completions = jsonDecode(existingJson);
      
      return completions.where((completion) {
        final completionDate = completion['date'] as String?;
        return completionDate == date;
      }).cast<Map<String, dynamic>>().toList();
    } catch (e) {
      print('❌ Error reading local completions: $e');
      return [];
    }
  }

  // Helper method to extract minutes from a daily plan's raw JSON
  // Minutes can be in training_minutes, total_minutes, or exercises_details
  // Handles both array format and object format with workouts/exercises/items properties
  int _extractMinutesFromPlanRaw(Map<String, dynamic> planRaw) {
    // Try training_minutes first (from daily_training_plans table)
    if (planRaw['training_minutes'] != null) {
      return int.tryParse(planRaw['training_minutes'].toString()) ?? 0;
    }
    
    // Try total_minutes
    if (planRaw['total_minutes'] != null) {
      return int.tryParse(planRaw['total_minutes'].toString()) ?? 0;
    }
    
    // Try to extract from exercises_details
    // Handle new structure: { workouts: [...], snapshots: [...] }
    // Also handle: array format, or object with workouts/exercises/items properties
    dynamic exercisesDetails = planRaw['exercises_details'];
    
    if (exercisesDetails == null) {
      return 0;
    }
    
    List<Map<String, dynamic>> exercises = [];
    
    // Handle array format
    if (exercisesDetails is List) {
      exercises = exercisesDetails.cast<Map<String, dynamic>>();
    }
    // Handle object format with workouts property (new backend structure)
    else if (exercisesDetails is Map<String, dynamic>) {
      // Check for workouts array (new backend structure)
      if (exercisesDetails['workouts'] is List) {
        exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
      }
      // Check for exercises array
      else if (exercisesDetails['exercises'] is List) {
        exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
      }
      // Check for items array
      else if (exercisesDetails['items'] is List) {
        exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
      }
    }
    // Handle JSON string format
    else if (exercisesDetails is String) {
      try {
        final parsed = jsonDecode(exercisesDetails);
        if (parsed is List) {
          exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else if (parsed is Map<String, dynamic>) {
          // Handle object format with workouts property
          if (parsed['workouts'] is List) {
            exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
          } else if (parsed['exercises'] is List) {
            exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
          } else if (parsed['items'] is List) {
            exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
          }
        }
      } catch (e) {
        print('⚠️ Stats - Failed to parse exercises_details JSON string: $e');
      }
    }
    
    // Sum minutes from all exercises
    return exercises.fold<int>(0, (sum, exercise) {
      if (exercise is Map<String, dynamic>) {
        final minutes = exercise['minutes'] ?? exercise['training_minutes'];
        return sum + (int.tryParse(minutes?.toString() ?? '0') ?? 0);
      }
      return sum;
    });
  }

  // Get total workouts completed this week (6 days, not 7)
  // Shows count of individual completed workouts in the current 6-day week period
  int getWeeklyCompletedWorkouts() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for weekly workouts');
      return 0;
    }
    
    // Filter dailyPlansRaw to only include active plan's data FIRST
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for weekly workouts');
      return 0;
    }
    
    // Only use UserStats if we have filtered plans (meaning we have data for the active plan)
    // UserStats might contain data from ALL plans, so we should calculate from filteredPlans instead
    // But if filteredPlans calculation is 0, we can use UserStats as a fallback (with caution)
    
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total (0-5 = 6 days)
    
    // Count individual completed workouts (not days)
    int totalWorkouts = 0;
    
    final planId = activePlanIds['planId'] as int?;
    final assignmentId = activePlanIds['assignmentId'] as int?;
    final planType = activePlanIds['planType'] as String?;
    
    // Check filtered dailyPlansRaw first (more reliable source from API)
    for (final planRaw in filteredPlans) {
      final planDateStr = planRaw['plan_date'] as String? ?? '';
      final planDate = DateTime.tryParse(planDateStr);
      if (planDate == null) continue;
      
      // Normalize plan date to midnight for accurate comparison (handles timezone differences)
      // Normalize to UTC date components to match backend UTC format
      final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
      final weekStartNormalized = DateTime.utc(weekStart.year, weekStart.month, weekStart.day);
      final weekEndNormalized = DateTime.utc(weekEnd.year, weekEnd.month, weekEnd.day);
      
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      
      if (isCompleted && 
          planDateNormalized.isAfter(weekStartNormalized.subtract(const Duration(days: 1))) &&
          planDateNormalized.isBefore(weekEndNormalized.add(const Duration(days: 1)))) {
        // Count individual workouts in this completed plan
        dynamic exercisesDetails = planRaw['exercises_details'];
        List<Map<String, dynamic>> exercises = [];
        
        // Handle new structure: { workouts: [...], snapshots: [...] }
        if (exercisesDetails is List) {
          exercises = exercisesDetails.cast<Map<String, dynamic>>();
        } else if (exercisesDetails is Map<String, dynamic>) {
          if (exercisesDetails['workouts'] is List) {
            exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['exercises'] is List) {
            exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['items'] is List) {
            exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
          }
        } else if (exercisesDetails is String) {
          try {
            final parsed = jsonDecode(exercisesDetails);
            if (parsed is List) {
              exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            } else if (parsed is Map<String, dynamic>) {
              if (parsed['workouts'] is List) {
                exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['exercises'] is List) {
                exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['items'] is List) {
                exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
              }
            }
          } catch (e) {
            print('⚠️ Stats - Failed to parse exercises_details in getWeeklyCompletedWorkouts: $e');
          }
        }
        
        // Count workouts that are completed (ONLY count completed workouts)
        for (final exercise in exercises) {
          if (exercise is Map<String, dynamic>) {
            final isWorkoutCompleted = exercise['is_completed'] as bool? ?? false;
            // Only count if:
            // 1. Workout is explicitly marked as completed (is_completed = true), OR
            // 2. Plan is fully completed (all workouts in a completed plan are considered completed)
            // DO NOT count workouts without is_completed flag unless plan is completed
            if (isWorkoutCompleted || isCompleted) {
              // If plan is completed, count all workouts (plan completion means all workouts done)
              // If plan is not completed, only count workouts explicitly marked as completed
              if (isCompleted) {
                totalWorkouts++;
              } else if (isWorkoutCompleted) {
                // Only count if workout is explicitly marked as completed
                totalWorkouts++;
              }
            }
          }
        }
      }
    }
    
    // REMOVED: Parsed dailyPlans fallback to avoid counting unfiltered plans
    // We already use filteredPlans from dailyPlansRaw, which is more accurate

    // IMPORTANT: Only count local completions if they're NOT already in the database
    // Local completions are only for workouts that failed to submit to the API
    // If a workout is in the database (filteredPlans), it's already counted above
    // REMOVED: Local completions counting to avoid double-counting
    
    // PRIORITY: Use UserStats from backend as primary source (backend calculates correctly)
    // Backend now creates separate stats records per plan type, so UserStats is filtered correctly
    if (userStats.value != null && filteredPlans.isNotEmpty) {
      // Use weeklyProgress.totalWorkouts from backend (most accurate)
      final weeklyTotalWorkouts = userStats.value!.weeklyProgress.totalWorkouts;
      if (weeklyTotalWorkouts > 0) {
        print('✅ Stats - Using UserStats weeklyProgress.totalWorkouts: $weeklyTotalWorkouts (database calculation: $totalWorkouts)');
        return weeklyTotalWorkouts;
      }
    }
    
    if (totalWorkouts > 0) {
      print('📊 Stats - Weekly completed workouts (individual count from dailyPlansRaw): $totalWorkouts');
    } else {
      print('📊 Stats - Weekly completed workouts (individual count): $totalWorkouts');
    }
    return totalWorkouts;
  }

  // Get total workouts completed this month (count till whole month - all days in month)
  int getMonthlyCompletedWorkouts() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for monthly workouts');
      return 0;
    }
    
    // Calculate from dailyPlansRaw FIRST (more accurate, filtered by active plan)
    int totalWorkouts = 0;
    
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for monthly workouts');
      return 0;
    }
    
    final planId = activePlanIds['planId'] as int?;
    final assignmentId = activePlanIds['assignmentId'] as int?;
    final planType = activePlanIds['planType'] as String?;
    
    // Count individual workouts from filtered dailyPlansRaw
    for (final planRaw in filteredPlans) {
      final planDateStr = planRaw['plan_date'] as String? ?? '';
      final planDate = DateTime.tryParse(planDateStr);
      if (planDate == null) continue;
      
      // Normalize plan date to midnight for accurate comparison
      // Normalize to UTC date components to match backend UTC format
      final planDateNormalized = DateTime.utc(planDate.year, planDate.month, planDate.day);
      final monthStartNormalized = DateTime.utc(monthStart.year, monthStart.month, monthStart.day);
      final monthEndNormalized = DateTime.utc(monthEnd.year, monthEnd.month, monthEnd.day);
      
      if (planDateNormalized.isAfter(monthStartNormalized.subtract(const Duration(days: 1))) &&
          planDateNormalized.isBefore(monthEndNormalized.add(const Duration(days: 1)))) {
        final isCompleted = planRaw['is_completed'] as bool? ?? false;
        
        // Count individual workouts in this plan
        dynamic exercisesDetails = planRaw['exercises_details'];
        List<Map<String, dynamic>> exercises = [];
        
        // Handle new structure: { workouts: [...], snapshots: [...] }
        if (exercisesDetails is List) {
          exercises = exercisesDetails.cast<Map<String, dynamic>>();
        } else if (exercisesDetails is Map<String, dynamic>) {
          if (exercisesDetails['workouts'] is List) {
            exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['exercises'] is List) {
            exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
          } else if (exercisesDetails['items'] is List) {
            exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
          }
        } else if (exercisesDetails is String) {
          try {
            final parsed = jsonDecode(exercisesDetails);
            if (parsed is List) {
              exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            } else if (parsed is Map<String, dynamic>) {
              if (parsed['workouts'] is List) {
                exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['exercises'] is List) {
                exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
              } else if (parsed['items'] is List) {
                exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
              }
            }
          } catch (e) {
            print('⚠️ Stats - Failed to parse exercises_details in getMonthlyCompletedWorkouts: $e');
          }
        }
        
        // Count workouts that are completed (ONLY count completed workouts)
        for (final exercise in exercises) {
          if (exercise is Map<String, dynamic>) {
            final isWorkoutCompleted = exercise['is_completed'] as bool? ?? false;
            // Only count if:
            // 1. Workout is explicitly marked as completed (is_completed = true), OR
            // 2. Plan is fully completed (all workouts in a completed plan are considered completed)
            // DO NOT count workouts without is_completed flag unless plan is completed
            if (isWorkoutCompleted || isCompleted) {
              // If plan is completed, count all workouts (plan completion means all workouts done)
              // If plan is not completed, only count workouts explicitly marked as completed
              if (isCompleted) {
                totalWorkouts++;
              } else if (isWorkoutCompleted) {
                // Only count if workout is explicitly marked as completed
                totalWorkouts++;
              }
            }
          }
        }
      }
    }
    
    // REMOVED: Parsed dailyPlans fallback to avoid counting unfiltered plans
    // We already use filteredPlans from dailyPlansRaw, which is more accurate

    // IMPORTANT: Only count local completions if they're NOT already in the database
    // Local completions are only for workouts that failed to submit to the API
    // If a workout is in the database (filteredPlans), it's already counted above
    // REMOVED: Local completions counting to avoid double-counting
    
    // PRIORITY: Use UserStats from backend as primary source (backend calculates correctly)
    // Backend now creates separate stats records per plan type, so UserStats is filtered correctly
    if (userStats.value != null && filteredPlans.isNotEmpty) {
      // Use monthlyProgress.totalWorkouts from backend (most accurate)
      final monthlyTotalWorkouts = userStats.value!.monthlyProgress.totalWorkouts;
      if (monthlyTotalWorkouts > 0) {
        print('✅ Stats - Using UserStats monthlyProgress.totalWorkouts: $monthlyTotalWorkouts (database calculation: $totalWorkouts)');
        return monthlyTotalWorkouts;
      }
    }
    
    print('📊 Stats - Monthly completed workouts (individual count from dailyPlansRaw): $totalWorkouts');
    return totalWorkouts;
  }

  // Helper function to calculate weekly batch sizes
  // Batch sizes: 12, 24, 34, 44, 54, ...
  int _getWeeklyBatchSize(int batchNumber) {
    if (batchNumber == 0) return 12;
    if (batchNumber == 1) return 24;
    return 24 + (batchNumber - 1) * 10; // 34, 44, 54, ...
  }

  // Helper function to calculate monthly batch sizes
  // Batch sizes: 30, 60, 90, 120, ...
  int _getMonthlyBatchSize(int batchNumber) {
    return 30 * (batchNumber + 1); // 30, 60, 90, 120, ...
  }

  // Get weekly progress with batching (6 days per batch, batch sizes: 12, 24, 34, 44, 54, ...)
  Map<String, dynamic> getWeeklyProgress() {
    // Check for active plan FIRST - if no active plan, return zero progress immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning zero weekly progress');
      return {
        'completed': 0,
        'remaining': 0,
        'total': 0,
        'total_minutes': 0,
        'total_workouts': 0,
        'batch_number': 0,
        'current_batch_size': 12,
        'next_batch_size': 24,
        'completed_workouts': 0,
        'incomplete_workouts': 0,
        'total_planned_workouts': 0,
        'completion_rate': 0.0,
      };
    }
    
    // Count unique days with completed workouts (not individual workouts)
    final completedDays = <String>{};
    int totalWorkouts = 0;
    int totalMinutes = 0;
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    
    // Count unique completed days and total workouts from filtered dailyPlansRaw
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      final completedAt = planRaw['completed_at'] as String?;
      
      if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
        // Use completed_at date for grouping (when completed today, use completed_at)
        final completedAtDate = DateTime.tryParse(completedAt);
        if (completedAtDate != null) {
          final dateStr = completedAtDate.toIso8601String().split('T').first;
          completedDays.add(dateStr);
          
          // Count individual workouts for this completed plan
          dynamic exercisesDetails = planRaw['exercises_details'];
          List<Map<String, dynamic>> exercises = [];
          
          if (exercisesDetails is List) {
            exercises = exercisesDetails.cast<Map<String, dynamic>>();
          } else if (exercisesDetails is Map<String, dynamic>) {
            if (exercisesDetails['workouts'] is List) {
              exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
            } else if (exercisesDetails['exercises'] is List) {
              exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
            } else if (exercisesDetails['items'] is List) {
              exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
            }
          }
          
          // Count all workouts in completed plan
          totalWorkouts += exercises.length;
          totalMinutes += _extractMinutesFromPlanRaw(planRaw);
        }
      }
    }
    
    // REMOVED: UserStats.dailyWorkouts fallback
    // UserStats.dailyWorkouts contains data from ALL plans of the same type (e.g., all manual plans)
    // It's not filtered by specific plan (approval_id or plan_id), so it would count workouts from other plans
    // We should only use filteredPlans to ensure accurate counts for the active plan
    
    final uniqueCompletedDays = completedDays.length;
    
    // Calculate batch number: Every 6 days = 1 batch
    // Batch 0 = Days 1-6, Batch 1 = Days 7-12, Batch 2 = Days 13-18, etc.
    final batchNumber = uniqueCompletedDays ~/ 6;
    
    // Get batch sizes
    final currentBatchSize = _getWeeklyBatchSize(batchNumber);
    final nextBatchSize = _getWeeklyBatchSize(batchNumber + 1);
    
    // Determine total for display:
    // If current batch not completed: Shows completed/currentBatchSize
    // If current batch completed: Shows completed/nextBatchSize
    final isCurrentBatchCompleted = uniqueCompletedDays >= (batchNumber + 1) * 6;
    final total = isCurrentBatchCompleted ? nextBatchSize : currentBatchSize;
    
    // Calculate remaining: total - completed
    final remaining = total > totalWorkouts ? total - totalWorkouts : 0;
    
    // Use UserStats if available (from new API) - prioritize backend data
    // But only if we have an active plan (otherwise we already returned zero progress)
    if (userStats.value != null && activePlanIds != null) {
      final wp = userStats.value!.weeklyProgress;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total
      
      // Use backend batch data if available, otherwise calculate from frontend
      final completed = wp.total > 0 ? wp.completed : totalWorkouts;
      final remainingCount = wp.total > 0 ? wp.remaining : remaining;
      final totalCount = wp.total > 0 ? wp.total : total;
      
      final completionRate = totalCount > 0 ? (completed / totalCount) * 100 : 0.0;
      return {
        // New keys
        'completed': completed,
        'remaining': remainingCount,
        'total': totalCount,
        'total_minutes': wp.totalMinutes > 0 ? wp.totalMinutes : totalMinutes,
        'total_workouts': wp.totalWorkouts > 0 ? wp.totalWorkouts : totalWorkouts,
        'batch_number': wp.batchNumber,
        'current_batch_size': wp.currentBatchSize,
        'next_batch_size': wp.nextBatchSize,
        'week_start': weekStart.toIso8601String().split('T').first,
        'week_end': weekEnd.toIso8601String().split('T').first,
        // Backward-compat keys used by UI
        'completed_workouts': completed,
        'incomplete_workouts': remainingCount,
        'total_planned_workouts': totalCount,
        'completion_rate': completionRate,
      };
    }
    
    // Calculate from frontend data (fallback)
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total (0-5 = 6 days)

    final completionRate = total > 0 ? (totalWorkouts / total) * 100 : 0.0;
    return {
      // New keys
      'completed': totalWorkouts,
      'remaining': remaining,
      'total': total,
      'total_minutes': totalMinutes,
      'total_workouts': totalWorkouts,
      'batch_number': batchNumber,
      'current_batch_size': currentBatchSize,
      'next_batch_size': nextBatchSize,
      'week_start': weekStart.toIso8601String().split('T').first,
      'week_end': weekEnd.toIso8601String().split('T').first,
      // Backward-compat keys used by UI
      'completed_workouts': totalWorkouts,
      'incomplete_workouts': remaining,
      'total_planned_workouts': total,
      'completion_rate': completionRate,
    };
  }

  // Get monthly progress with batching (30 days per batch, batch sizes: 30, 60, 90, 120, ...)
  Map<String, dynamic> getMonthlyProgress() {
    // Check for active plan FIRST - if no active plan, return zero progress immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning zero monthly progress');
      return {
        'completed': 0,
        'remaining': 0,
        'total': 0,
        'completion_rate': 0.0,
        'daily_average': 0.0,
        'days_passed': 0,
        'total_minutes': 0,
        'total_workouts': 0,
        'batch_number': 0,
        'batch_size': 30,
        'completed_workouts': 0,
        'incomplete_workouts': 0,
        'total_planned_workouts': 0,
      };
    }
    
    // Declare date variables at the beginning
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    
    // Get plan's start_date to calculate day numbers
    DateTime? planStartDate;
    if (Get.isRegistered<PlansController>()) {
      final plansController = Get.find<PlansController>();
      if (plansController.activePlan != null) {
        final activePlan = plansController.activePlan!;
        final startDateStr = activePlan['start_date']?.toString();
        if (startDateStr != null) {
          planStartDate = DateTime.tryParse(startDateStr);
        }
      }
    }
    
    // Count unique plan day numbers (not calendar dates) with completed workouts
    final completedDayNumbers = <int>{};
    int totalWorkouts = 0;
    int totalMinutes = 0;
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    
    // Count unique completed plan days and total workouts from filtered dailyPlansRaw
    // Filter by current month for accurate monthly progress
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      final completedAt = planRaw['completed_at'] as String?;
      
      if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
        // Calculate day number from plan_date relative to start_date
        final planDateStr = planRaw['plan_date'] as String? ?? '';
        if (planDateStr.isNotEmpty && planStartDate != null) {
          final planDateObj = DateTime.tryParse(planDateStr);
          if (planDateObj != null) {
            final daysDiff = planDateObj.difference(planStartDate).inDays;
            final dayNumber = daysDiff + 1; // Day 1 = start_date, Day 2 = start_date + 1, etc.
            
            if (dayNumber >= 1) {
              // Check if completion date is within current month
              final completedAtDate = DateTime.tryParse(completedAt);
              if (completedAtDate != null) {
                // Normalize to UTC date components to match backend UTC format
                final dateNormalized = DateTime.utc(completedAtDate.year, completedAtDate.month, completedAtDate.day);
                final monthStartNormalized = DateTime.utc(monthStart.year, monthStart.month, monthStart.day);
                final monthEndNormalized = DateTime.utc(monthEnd.year, monthEnd.month, monthEnd.day);
                
                // Only count days within the current month
                if (dateNormalized.isAfter(monthStartNormalized.subtract(const Duration(days: 1))) &&
                    dateNormalized.isBefore(monthEndNormalized.add(const Duration(days: 1)))) {
                  completedDayNumbers.add(dayNumber);
                  
                  // Count individual workouts for this completed plan
                  dynamic exercisesDetails = planRaw['exercises_details'];
                  List<Map<String, dynamic>> exercises = [];
                  
                  if (exercisesDetails is List) {
                    exercises = exercisesDetails.cast<Map<String, dynamic>>();
                  } else if (exercisesDetails is Map<String, dynamic>) {
                    if (exercisesDetails['workouts'] is List) {
                      exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
                    } else if (exercisesDetails['exercises'] is List) {
                      exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
                    } else if (exercisesDetails['items'] is List) {
                      exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
                    }
                  }
                  
                  // Count all workouts in completed plan
                  totalWorkouts += exercises.length;
                  totalMinutes += _extractMinutesFromPlanRaw(planRaw);
                }
              }
            }
          }
        }
      }
    }
    
    // REMOVED: UserStats.dailyWorkouts fallback
    // UserStats.dailyWorkouts contains data from ALL plans of the same type (e.g., all manual plans)
    // It's not filtered by specific plan (approval_id or plan_id), so it would count workouts from other plans
    // We should only use filteredPlans to ensure accurate counts for the active plan
    
    final uniqueCompletedDays = completedDayNumbers.length;
    
    print('📊 Stats - Monthly Progress Calculation:');
    print('📊 Stats - uniqueCompletedDays: $uniqueCompletedDays');
    print('📊 Stats - totalWorkouts: $totalWorkouts');
    
    // Calculate batch number: Every 30 days = 1 batch
    // Batch 0 = Days 1-30, Batch 1 = Days 31-60, Batch 2 = Days 61-90, etc.
    final batchNumber = uniqueCompletedDays ~/ 30;
    
    // Get batch size
    final batchSize = _getMonthlyBatchSize(batchNumber);
    final nextBatchSize = _getMonthlyBatchSize(batchNumber + 1);
    
    // Determine total for display:
    // If current batch not completed: Shows completed/batchSize
    // If current batch completed: Shows completed/nextBatchSize
    final isCurrentBatchCompleted = uniqueCompletedDays >= (batchNumber + 1) * 30;
    final total = isCurrentBatchCompleted ? nextBatchSize : batchSize;
    
    // IMPORTANT: Monthly progress shows completed DAYS, not completed workouts
    // Calculate remaining: total - completed (using days, not workouts)
    final remaining = total > uniqueCompletedDays ? total - uniqueCompletedDays : 0;
    
    // Calculate completion rate: based on completed days, not individual workouts
    // For monthly progress, completion rate should be: (uniqueCompletedDays / batchSize) * 100
    final completionRate = batchSize > 0 ? (uniqueCompletedDays / batchSize) * 100 : 0.0;
    
    print('📊 Stats - batchSize: $batchSize');
    print('📊 Stats - completionRate: ${completionRate.toStringAsFixed(1)}%');
    
    // Calculate days passed: count unique days with completed workouts (not current day of month)
    final daysPassed = uniqueCompletedDays; // Use unique completed days, not current day of month
    print('📊 Stats - daysPassed: $daysPassed');
    final dailyAverage = daysPassed > 0 ? uniqueCompletedDays / daysPassed : 0.0;
    
    // Use UserStats if available (from new API) - prioritize backend data
    // But only if we have an active plan (otherwise we already returned zero progress)
    if (userStats.value != null && activePlanIds != null) {
      final mp = userStats.value!.monthlyProgress;
      
      // IMPORTANT: Monthly progress shows completed DAYS, not completed workouts
      // Use uniqueCompletedDays from backend if available, otherwise use frontend calculation
      final completedDays = mp.daysPassed > 0 ? mp.daysPassed : uniqueCompletedDays;
      final totalCount = mp.total > 0 ? mp.total : total;
      final remainingDays = totalCount > completedDays ? totalCount - completedDays : 0;
      
      // ALWAYS calculate completion rate from uniqueCompletedDays (ignore backend value)
      // Completion rate should be: (uniqueCompletedDays / batchSize) * 100
      final finalCompletionRate = batchSize > 0 ? (uniqueCompletedDays / batchSize) * 100 : 0.0;
      
      // ALWAYS use uniqueCompletedDays for days_passed (ignore backend value)
      // Days passed should be the count of unique days with completed workouts
      final finalDaysPassed = uniqueCompletedDays;

    return {
        // New keys
        'completed': completedDays, // Show completed DAYS, not workouts
        'remaining': remainingDays,
        'total': totalCount,
        'completion_rate': finalCompletionRate,
        'daily_average': mp.dailyAvg > 0 ? mp.dailyAvg.toDouble() : dailyAverage,
        'days_passed': finalDaysPassed,
        'total_minutes': mp.totalMinutes > 0 ? mp.totalMinutes : totalMinutes,
        'total_workouts': mp.totalWorkouts > 0 ? mp.totalWorkouts : totalWorkouts,
        'batch_number': mp.batchNumber,
        'batch_size': mp.batchSize,
        'days_in_month': monthEnd.day,
        'month_start': monthStart.toIso8601String().split('T').first,
        'month_end': monthEnd.toIso8601String().split('T').first,
        // Backward-compat keys used by UI
        'completed_workouts': completedDays, // Show days, not workouts
        'incomplete_workouts': remainingDays,
        'total_planned_workouts': totalCount,
      };
    }
    
    // Calculate from frontend data (fallback)
    // Reuse 'now', 'monthStart', and 'monthEnd' variables declared at the beginning

    return {
      // New keys
      'completed': uniqueCompletedDays, // Show completed DAYS, not workouts
      'remaining': remaining,
      'total': total,
      'completion_rate': completionRate,
      'daily_average': dailyAverage,
      'days_passed': daysPassed,
      'total_minutes': totalMinutes,
      'total_workouts': totalWorkouts,
      'batch_number': batchNumber,
      'batch_size': batchSize,
      'days_in_month': monthEnd.day,
      'month_start': monthStart.toIso8601String().split('T').first,
      'month_end': monthEnd.toIso8601String().split('T').first,
      // Backward-compat keys used by UI
      'completed_workouts': uniqueCompletedDays, // Show days, not workouts
      'incomplete_workouts': remaining,
      'total_planned_workouts': total,
    };
  }

  // Get workouts by category
  Map<String, int> getWorkoutsByCategory() {
    final Map<String, int> categoryCount = {};
    
    for (final plan in dailyPlans) {
      if (plan.isCompleted) {
        categoryCount[plan.planCategory] = (categoryCount[plan.planCategory] ?? 0) + 1;
      }
    }
    
    return categoryCount;
  }

  // Get recent workouts (last 6 days, not 7) - show all workout names
  List<Map<String, dynamic>> getRecentWorkouts({int days = 6}) {
    // Check for active plan FIRST - if no active plan, return empty list immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning empty list for recent workouts');
      return [];
    }
    
    final now = DateTime.now();
    final today = now.toIso8601String().split('T').first;
    
    // PRIORITY: Always check UserStats.dailyWorkouts first (from stats_daily_workouts column)
    // This is the most reliable source as it comes from the stats sync
    // BUT: We must validate that dates in dailyWorkouts actually have completed plans
    // activePlanIds is already checked, so it's not null here
    if (userStats.value != null && userStats.value!.dailyWorkouts.isNotEmpty) {
      print('📊 Stats - Using UserStats.dailyWorkouts as primary source (from stats_daily_workouts column)');
      print('📊 Stats - Found ${userStats.value!.dailyWorkouts.length} days in dailyWorkouts');
      
      final result = <Map<String, dynamic>>[];
      
      // VALIDATE: Only include dates that have actually completed plans
      // Filter dailyPlansRaw to only include active plan's data
      final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
      
      // Build a set of valid completed dates from filtered dailyPlansRaw (if available)
      // If filteredPlans is empty, trust dailyWorkouts from backend (it comes from stats sync)
      final validCompletedDates = <String>{};
      if (filteredPlans.isNotEmpty) {
        // Only validate if we have filtered dailyPlansRaw data
        for (final planRaw in filteredPlans) {
          final isCompleted = planRaw['is_completed'] as bool? ?? false;
          final completedAt = planRaw['completed_at'] as String?;
          
          // Must have BOTH is_completed: true AND completed_at timestamp
          if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
            // Use completed_at date for grouping (this is what backend should use)
            final completedAtDate = DateTime.tryParse(completedAt);
            if (completedAtDate != null) {
              final completedDateStr = completedAtDate.toIso8601String().split('T').first;
              validCompletedDates.add(completedDateStr);
            }
            
            // Also check plan_date as fallback (in case backend groups by plan_date)
            final planDate = planRaw['plan_date'] as String?;
            if (planDate != null) {
              final planDateObj = DateTime.tryParse(planDate);
              if (planDateObj != null) {
                final planDateStr = planDateObj.toIso8601String().split('T').first;
                validCompletedDates.add(planDateStr);
              }
            }
          }
        }
        print('📊 Stats - Validated ${validCompletedDates.length} completed dates from filtered dailyPlansRaw (active plan only)');
        print('📊 Stats - Valid completed dates: ${validCompletedDates.toList()}');
      } else if (dailyPlansRaw.isEmpty) {
        print('📊 Stats - dailyPlansRaw is empty, trusting dailyWorkouts from backend stats sync');
      } else {
        print('📊 Stats - No active plan, filtering out all dates from dailyWorkouts');
      }
      
      // Filter statsDates to only include dates that have completed plans (if validation data available)
      // IMPORTANT: Don't filter by date being "future" - backend groups by plan_date which can be in the future
      // Instead, check if there are actually completed plans for that date
      // If dailyPlansRaw is empty, trust dailyWorkouts (it comes from backend stats sync)
      final statsDates = userStats.value!.dailyWorkouts.keys.where((dateStr) {
        final date = DateTime.tryParse(dateStr);
        if (date == null) return false;
        
        // Only validate against filtered dailyPlansRaw if we have validation data
        // If filteredPlans is empty, trust dailyWorkouts from backend (it comes from stats sync)
        if (filteredPlans.isNotEmpty && validCompletedDates.isNotEmpty) {
          // Normalize to UTC date components to match backend UTC format
          final dateNormalized = DateTime.utc(date.year, date.month, date.day);
          final dateStrNormalized = dateNormalized.toIso8601String().split('T').first;
          
          // Check if this date has a completed plan (either by plan_date or completed_at)
          if (!validCompletedDates.contains(dateStrNormalized) && !validCompletedDates.contains(dateStr)) {
            print('⚠️ Stats - Filtering out date without completed plans: $dateStr');
            return false;
          }
        }
        
        // If dailyPlansRaw is empty, trust all dates from dailyWorkouts (backend has validated them)
        return true;
    }).toList()
        ..sort((a, b) {
          final aDate = DateTime.tryParse(a);
          final bDate = DateTime.tryParse(b);
          if (aDate == null || bDate == null) return 0;
          return aDate.compareTo(bDate); // Oldest first (for sequential day numbering)
        });
      
      print('📊 Stats - Found ${statsDates.length} validated completed dates in dailyWorkouts (after filtering)');
      
      // Assign sequential day numbers and determine window
      final Map<String, int> dateToDayNumber = {};
      int sequentialDayNumber = 1;
      for (final date in statsDates) {
        dateToDayNumber[date] = sequentialDayNumber;
        sequentialDayNumber++;
      }
      
      // Determine which 6-day window to show
      if (dateToDayNumber.isNotEmpty) {
        final highestDayNumber = dateToDayNumber.values.reduce((a, b) => a > b ? a : b);
        final windowNumber = ((highestDayNumber - 1) ~/ days) + 1;
        final windowStartDay = (windowNumber - 1) * days + 1;
        final windowEndDay = windowNumber * days;
        
        print('📊 Stats - Highest completed day: $highestDayNumber, Window: $windowNumber (Day $windowStartDay-$windowEndDay)');
        
        // Filter dates to only show days in the current window
        final datesInWindow = dateToDayNumber.entries
            .where((entry) => entry.value >= windowStartDay && entry.value <= windowEndDay)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value)); // Sort by day number (ascending)
        
        print('📊 Stats - Filtered to ${datesInWindow.length} days in window $windowNumber');
        
        // Build result with days from current window
        for (final entry in datesInWindow) {
          final date = entry.key;
          final dayNumber = entry.value;
          final workoutNames = userStats.value!.dailyWorkouts[date] ?? [];
          
          if (workoutNames.isNotEmpty) {
            // Format: "Day X: workout1, workout2, ..."
            final workoutNamesStr = workoutNames.join(', ');
            final workoutCount = workoutNames.length; // Count of workouts for this day
            result.add({
              'day': dayNumber,
              'day_label': 'Day $dayNumber',
              'date': date,
              'workout_names': workoutNames,
              'workout_names_str': workoutNamesStr,
              'workout_count': workoutCount, // Add count for this day
              'workout_name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)', // Include count in display
              'name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)', // Include count in display
            });
          }
        }
        
        print('📊 Stats - Showing ${result.length} days from window $windowNumber (Day $windowStartDay-$windowEndDay) from dailyWorkouts');
      }
      
      // If we got results from dailyWorkouts, return early (don't use dailyPlansRaw)
      if (result.isNotEmpty) {
        print('📊 Stats - Using dailyWorkouts data (${result.length} days)');
        return result;
      }
    }
    
    // FALLBACK: If dailyWorkouts is empty, use dailyPlansRaw
    // IMPORTANT: Filter by active plan FIRST to avoid counting workouts from other plans
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      print('🔍 Stats - No matching plans for active plan in getRecentWorkouts, returning empty list');
      return [];
    }
    
    // Get all completed plans from filtered plans - MUST have BOTH is_completed: true AND completed_at timestamp
    // This aligns with backend validation that requires both fields
    final allCompletedPlans = filteredPlans.where((planRaw) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      final completedAt = planRaw['completed_at'] as String?;
      final planId = planRaw['id'] ?? 'N/A';
      final planDate = planRaw['plan_date'] ?? 'N/A';
      final planType = planRaw['plan_type'] ?? 'N/A';
      final sourcePlanId = planRaw['source_plan_id'] ?? 'N/A';
      
      // Validate: must have BOTH is_completed: true AND completed_at timestamp
      if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
        print('✅ Stats - Found completed plan: id=$planId, date=$planDate, type=$planType, sourcePlanId=$sourcePlanId, completedAt=$completedAt');
        return true;
      }
      
      // Log warning if plan has is_completed: true but no completed_at (incomplete plan)
      if (isCompleted && (completedAt == null || completedAt.isEmpty)) {
        print('⚠️ Stats - WARNING: Plan $planId (date=$planDate, type=$planType) has is_completed=true but no completed_at timestamp! Filtering out.');
      }
      
      return false;
    }).toList();
    
    print('📊 Stats - Found ${allCompletedPlans.length} completed plans with both is_completed=true and completed_at timestamp');
    
    // Debug: Log all plans to see why they're not being counted
    if (allCompletedPlans.isEmpty && filteredPlans.isNotEmpty) {
      print('⚠️ Stats - DEBUG: No completed plans found, but ${filteredPlans.length} filtered plans exist');
      print('⚠️ Stats - DEBUG: Checking each plan for completion status...');
      for (final planRaw in filteredPlans.take(10)) { // Log first 10 plans
        final isCompleted = planRaw['is_completed'] as bool? ?? false;
        final completedAt = planRaw['completed_at'] as String?;
        final planId = planRaw['id'] ?? 'N/A';
        final planDate = planRaw['plan_date'] as String? ?? 'N/A';
        print('⚠️ Stats - DEBUG: Plan $planId: is_completed=$isCompleted, completed_at=$completedAt, plan_date=$planDate');
      }
    }
    
    // Sort by completed_at date (most recent first), fallback to plan_date
    allCompletedPlans.sort((a, b) {
      final aCompletedAt = a['completed_at'] as String?;
      final bCompletedAt = b['completed_at'] as String?;
      
      DateTime? aDate, bDate;
      if (aCompletedAt != null) {
        aDate = DateTime.tryParse(aCompletedAt);
      }
      if (bCompletedAt != null) {
        bDate = DateTime.tryParse(bCompletedAt);
      }
      
      // Fallback to plan_date if completed_at is not available
      if (aDate == null) {
        final aPlanDate = a['plan_date'] as String?;
        aDate = aPlanDate != null ? DateTime.tryParse(aPlanDate) : null;
      }
      if (bDate == null) {
        final bPlanDate = b['plan_date'] as String?;
        bDate = bPlanDate != null ? DateTime.tryParse(bPlanDate) : null;
      }
      
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate); // Most recent first
    });
    
    // Get plan's start_date to calculate day numbers
    DateTime? planStartDate;
    if (Get.isRegistered<PlansController>()) {
      final plansController = Get.find<PlansController>();
      if (plansController.activePlan != null) {
        final activePlan = plansController.activePlan!;
        final startDateStr = activePlan['start_date']?.toString();
        if (startDateStr != null) {
          planStartDate = DateTime.tryParse(startDateStr);
        }
      }
    }
    
    // If start_date not found, try to get it from SchedulesController (for assigned plans)
    if (planStartDate == null && Get.isRegistered<SchedulesController>()) {
      final schedulesController = Get.find<SchedulesController>();
      if (schedulesController.activeSchedule != null) {
        final activeSchedule = schedulesController.activeSchedule!;
        // For assigned plans, get start_date from assignment
        final startDateStr = activeSchedule['start_date']?.toString();
        if (startDateStr != null) {
          planStartDate = DateTime.tryParse(startDateStr);
          print('📊 Stats - Got start_date from activeSchedule: $startDateStr');
        }
      }
    }
    
    // Group by plan day number (calculated from plan_date relative to start_date)
    // This ensures Day 1 and Day 2 are separate even if completed on same calendar date
    final Map<int, List<String>> workoutsByDayNumber = {};
    
    for (final planRaw in allCompletedPlans) {
      // Get plan_date (this is the scheduled date for this day of the plan)
      final planDateStr = planRaw['plan_date'] as String? ?? '';
      if (planDateStr.isEmpty) continue;
      
      final planDateObj = DateTime.tryParse(planDateStr);
      if (planDateObj == null) continue;
      
      // Calculate day number from plan_date relative to start_date
      int dayNumber = 1; // Default to day 1 if start_date not available
      if (planStartDate != null) {
        final daysDiff = planDateObj.difference(planStartDate).inDays;
        dayNumber = daysDiff + 1; // Day 1 = start_date, Day 2 = start_date + 1, etc.
        if (dayNumber < 1) dayNumber = 1; // Ensure positive day number
      } else {
        // If start_date not available, use plan_date as fallback (group by calendar date)
        // But this is not ideal - we should have start_date
        final planDate = planDateObj.toIso8601String().split('T').first;
        // Try to infer day number from order of completion dates
        // This is a fallback - ideally we should always have start_date
      }
      
      // Extract workout names from exercises_details
      final workouts = <String>[];
      dynamic exercisesDetails = planRaw['exercises_details'];
      List<Map<String, dynamic>> exercises = [];
      
      // Handle array format
      if (exercisesDetails is List) {
        exercises = exercisesDetails.cast<Map<String, dynamic>>();
      }
      // Handle object format with workouts property (new backend structure)
      else if (exercisesDetails is Map<String, dynamic>) {
        if (exercisesDetails['workouts'] is List) {
          exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
        } else if (exercisesDetails['exercises'] is List) {
          exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
        } else if (exercisesDetails['items'] is List) {
          exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
        }
      }
      // Handle JSON string format
      else if (exercisesDetails is String) {
        try {
          final parsed = jsonDecode(exercisesDetails);
          if (parsed is List) {
            exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else if (parsed is Map<String, dynamic>) {
            if (parsed['workouts'] is List) {
              exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
            } else if (parsed['exercises'] is List) {
              exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
            } else if (parsed['items'] is List) {
              exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
            }
          }
        } catch (e) {
          print('⚠️ Stats - Failed to parse exercises_details JSON string in getRecentWorkouts: $e');
        }
      }
      
      if (exercises.isNotEmpty) {
        for (final exercise in exercises) {
          if (exercise is Map<String, dynamic>) {
            // Only count completed workouts (is_completed: true) or if plan is fully completed
            final isWorkoutCompleted = exercise['is_completed'] as bool? ?? false;
            final isPlanCompleted = planRaw['is_completed'] as bool? ?? false;
            
            // Only add workout if it's explicitly completed OR plan is fully completed
            // (if plan is completed, all workouts in it are considered completed)
            if (isWorkoutCompleted || isPlanCompleted) {
              final workoutName = exercise['workout_name'] ?? 
                                 exercise['name'] ?? 
                                 exercise['exercise_name'] ?? 
                                 'Unknown';
              workouts.add(workoutName.toString());
            }
          }
        }
      }
      
      // REMOVED: Don't add workout_name at plan level to avoid duplication
      // The exercises_details already contains all workouts for the plan
      // Adding plan-level workout_name would duplicate workouts that are already in exercises_details
      
      if (workouts.isNotEmpty) {
        // Group workouts by day number (if multiple plans on same day, combine workouts)
        // IMPORTANT: For manual plans, each day should have ONE plan entry with multiple workouts
        // If we're seeing multiple plans per day, we need to combine them correctly
        if (workoutsByDayNumber.containsKey(dayNumber)) {
          // Combine workouts from multiple plans on the same day
          final beforeCount = workoutsByDayNumber[dayNumber]!.length;
          workoutsByDayNumber[dayNumber]!.addAll(workouts);
          // Remove duplicates (in case same workout appears in multiple plans)
          workoutsByDayNumber[dayNumber] = workoutsByDayNumber[dayNumber]!.toSet().toList();
          final afterCount = workoutsByDayNumber[dayNumber]!.length;
          print('📊 Stats - Combined workouts for Day $dayNumber: $beforeCount → $afterCount unique workouts (added ${workouts.length} from plan ${planRaw['id']}, workouts: ${workouts.join(", ")})');
        } else {
          workoutsByDayNumber[dayNumber] = workouts;
          print('📊 Stats - Added workouts for Day $dayNumber: ${workouts.length} workouts from plan ${planRaw['id']} (workouts: ${workouts.join(", ")})');
        }
      } else {
        print('⚠️ Stats - Plan ${planRaw['id']} for Day $dayNumber has no workouts in exercises_details');
      }
    }
    
    // Convert to list format grouped by day number (Day 1, Day 2, etc.)
    // Implement sliding window: After Day 7 completes, hide Day 1-6 and show Day 7-12
    final result = <Map<String, dynamic>>[];
    
    // Step 1: Get all day numbers and sort them
    final sortedDayNumbers = workoutsByDayNumber.keys.toList()..sort();
    
    print('📊 Stats - Found ${sortedDayNumbers.length} completed days: ${sortedDayNumbers.join(", ")}');
    print('📊 Stats - Workouts by day breakdown:');
    for (final entry in workoutsByDayNumber.entries) {
      print('  - Day ${entry.key}: ${entry.value.join(", ")} (${entry.value.length} total)');
    }
    
    // Step 2: Use day numbers directly (no need to reassign - they're already correct)
    final Map<int, int> dayNumberToDisplayNumber = {};
    for (final dayNum in sortedDayNumbers) {
      dayNumberToDisplayNumber[dayNum] = dayNum; // Day number is already correct
    }
    
    // Step 3: Determine which 6-day window to show based on the highest completed day
    if (dayNumberToDisplayNumber.isEmpty) {
      print('📊 Stats - No completed days found, returning empty result');
      return result; // No completed plans
    }
    
    final highestDayNumber = sortedDayNumbers.reduce((a, b) => a > b ? a : b);
    // Calculate which window the highest day belongs to (window 1 = Day 1-6, window 2 = Day 7-12, etc.)
    final windowNumber = ((highestDayNumber - 1) ~/ days) + 1;
    // Calculate window range
    final windowStartDay = (windowNumber - 1) * days + 1;
    final windowEndDay = windowNumber * days;
    
    print('📊 Stats - Highest completed day: $highestDayNumber, Window: $windowNumber (Day $windowStartDay-$windowEndDay)');
    
    // Step 4: Filter day numbers to only show days in the current window
    final daysInWindow = sortedDayNumbers
        .where((dayNum) => dayNum >= windowStartDay && dayNum <= windowEndDay)
        .toList()
      ..sort(); // Sort by day number (ascending)
    
    print('📊 Stats - Filtered to ${daysInWindow.length} days in window $windowNumber');
    
    // Step 5: Build result with days from current window
    for (final dayNumber in daysInWindow) {
      final workoutNames = workoutsByDayNumber[dayNumber]!;
      
      if (workoutNames.isNotEmpty) {
        // Format: "Day X: workout1, workout2, ..."
        final workoutNamesStr = workoutNames.join(', ');
        final workoutCount = workoutNames.length; // Count of workouts for this day
        result.add({
          'day': dayNumber,
          'day_label': 'Day $dayNumber',
          'date': '', // No longer using calendar date for grouping
          'workout_names': workoutNames,
          'workout_names_str': workoutNamesStr,
          'workout_count': workoutCount, // Add count for this day
          'workout_name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)', // Include count in display
          'name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)', // Include count in display
        });
      }
    }
    
    print('📊 Stats - Showing ${result.length} days from window $windowNumber (Day $windowStartDay-$windowEndDay)');
    
    // If still no results, try UserStats.recentWorkouts as last fallback (flat list from stats_recent_workouts)
    if (result.isEmpty && userStats.value != null && userStats.value!.recentWorkouts.isNotEmpty) {
      print('📊 Stats - dailyPlansRaw and dailyWorkouts are empty, using UserStats.recentWorkouts as fallback');
      print('📊 Stats - Found ${userStats.value!.recentWorkouts.length} workouts in recentWorkouts');
      
      // recentWorkouts is a flat list, so we'll group them by day based on order
      // Since we don't have dates, we'll just show them as Day 1, Day 2, etc.
      // Assuming 2 workouts per day (common pattern)
      final workoutsPerDay = 2;
      int dayNumber = 1;
      int currentDayWorkouts = 0;
      List<String> currentDayWorkoutNames = [];
      
      for (int i = 0; i < userStats.value!.recentWorkouts.length && dayNumber <= days; i++) {
        final workoutName = userStats.value!.recentWorkouts[i];
        currentDayWorkoutNames.add(workoutName);
        currentDayWorkouts++;
        
        // If we've reached workoutsPerDay or this is the last workout, create a day entry
        if (currentDayWorkouts >= workoutsPerDay || i == userStats.value!.recentWorkouts.length - 1) {
          if (currentDayWorkoutNames.isNotEmpty) {
            final workoutNamesStr = currentDayWorkoutNames.join(', ');
            final workoutCount = currentDayWorkoutNames.length;
            result.add({
              'day': dayNumber,
              'day_label': 'Day $dayNumber',
              'date': '', // No date available from flat list
              'workout_names': List<String>.from(currentDayWorkoutNames),
              'workout_names_str': workoutNamesStr,
              'workout_count': workoutCount,
              'workout_name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)',
              'name': 'Day $dayNumber: $workoutNamesStr ($workoutCount)',
            });
            dayNumber++;
            currentDayWorkoutNames.clear();
            currentDayWorkouts = 0;
          }
        }
      }
      
      print('📊 Stats - Converted ${result.length} days from UserStats.recentWorkouts');
    }
    
    return result;
  }

  // Get current streak (count plan days: if all workouts of a day are completed, count as 1)
  // Counts consecutive plan days (Day 1, Day 2, Day 3, etc.), not calendar dates
  int getCurrentStreak() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for current streak');
      return 0;
    }
    
    // NOTE: Don't use UserStats.longestStreak - that's the longest streak ever, not current streak
    // We need to calculate current streak from consecutive completed plan days
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for current streak');
      return 0;
    }
    
    // Get plan's start_date to calculate day numbers
    DateTime? planStartDate;
    if (Get.isRegistered<PlansController>()) {
      final plansController = Get.find<PlansController>();
      if (plansController.activePlan != null) {
        final activePlan = plansController.activePlan!;
        final startDateStr = activePlan['start_date']?.toString();
        if (startDateStr != null) {
          planStartDate = DateTime.tryParse(startDateStr);
        }
      }
    }
    
    // Get unique completed plan day numbers (not calendar dates)
    final completedDayNumbers = <int>{};
    
    // Check filtered dailyPlansRaw first (more reliable source from API)
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      
      if (isCompleted) {
        // Calculate day number from plan_date relative to start_date
        final planDateStr = planRaw['plan_date'] as String? ?? '';
        if (planDateStr.isNotEmpty && planStartDate != null) {
          final planDateObj = DateTime.tryParse(planDateStr);
          if (planDateObj != null) {
            final daysDiff = planDateObj.difference(planStartDate).inDays;
            final dayNumber = daysDiff + 1; // Day 1 = start_date, Day 2 = start_date + 1, etc.
            if (dayNumber >= 1) {
              completedDayNumbers.add(dayNumber);
            }
          }
        }
      }
    }
    
    if (completedDayNumbers.isEmpty) {
      print('📊 Stats - Current streak: 0 (no completed plan days)');
      return 0;
    }
    
    // Sort day numbers in descending order (most recent first)
    final sortedDayNumbers = completedDayNumbers.toList()..sort((a, b) => b.compareTo(a));
    
    // Count consecutive days starting from the highest day number
    int streak = 1;
    int expectedDay = sortedDayNumbers[0]; // Start from the highest completed day
    
    // Count backwards: if Day 2 is completed, check Day 1, then Day 0, etc.
    for (int i = 1; i < sortedDayNumbers.length; i++) {
      final currentDay = sortedDayNumbers[i];
      expectedDay--; // We expect the next day to be (expectedDay - 1)
      
      if (currentDay == expectedDay) {
        streak++; // Consecutive day found
      } else {
        break; // Streak broken (gap found)
      }
    }
    
    print('📊 Stats - Current streak: $streak days (completed days: ${sortedDayNumbers.join(", ")})');
    return streak;
  }

  // Get remaining tasks for today
  List<DailyTrainingPlan> getTodaysRemainingTasks() {
    final today = DateTime.now().toIso8601String().split('T').first;
    return dailyPlans.where((plan) => 
      plan.planDate == today && !plan.isCompleted
    ).toList();
  }

  // Get remaining tasks for this week (6 days, not 7)
  List<DailyTrainingPlan> getWeeklyRemainingTasks() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total
    
    return dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && 
             planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList();
  }

  // Get remaining tasks for this month
  List<DailyTrainingPlan> getMonthlyRemainingTasks() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    
    return dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && 
             planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).toList();
  }

  // Get overdue tasks (past due date and not completed)
  List<DailyTrainingPlan> getOverdueTasks() {
    final today = DateTime.now();
    return dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && planDate.isBefore(today);
    }).toList()
    ..sort((a, b) => a.planDate.compareTo(b.planDate));
  }

  // Get upcoming tasks (future dates)
  List<DailyTrainingPlan> getUpcomingTasks({int days = 7}) {
    final now = DateTime.now();
    final futureDate = now.add(Duration(days: days));
    
    return dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && 
             planDate.isAfter(now) && 
             planDate.isBefore(futureDate);
    }).toList()
    ..sort((a, b) => a.planDate.compareTo(b.planDate));
  }

  // Get remaining tasks: use backend data from UserStats.remainingTasks
  Map<String, dynamic> getRemainingTasks() {
    // Use UserStats if available (from new API)
    if (userStats.value != null) {
      final rt = userStats.value!.remainingTasks;
      return {
        'today': rt.today.length,
        'week': rt.weekly.length,
        'month': rt.monthly.length,
        'upcoming': rt.upcoming.length,
      };
    }
    
    // Fallback: calculate from daily plans (should match backend logic)
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T').first;
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total
    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    
    // Today's remaining tasks (incomplete plans for today)
    final todaysRemaining = dailyPlans.where((plan) {
      final planDateStr = plan.planDate.split('T').first;
      return !plan.isCompleted && planDateStr == todayStr;
    }).length;
    
    // Weekly remaining tasks (incomplete plans in the week, including today)
    final weeklyRemaining = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      final todayNormalized = DateTime.tryParse(todayStr);
      if (planDateNormalized == null || todayNormalized == null) return false;
      return !plan.isCompleted && 
             (planDateNormalized.isAfter(todayNormalized) || planDateNormalized.isAtSameMomentAs(todayNormalized)) && // Changed from > to >= to include today
             planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).length;
    
    // Monthly remaining tasks (incomplete plans in the month, including today)
    final monthlyRemaining = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      final todayNormalized = DateTime.tryParse(todayStr);
      if (planDateNormalized == null || todayNormalized == null) return false;
      return !plan.isCompleted && 
             (planDateNormalized.isAfter(todayNormalized) || planDateNormalized.isAtSameMomentAs(todayNormalized)) && // Changed from > to >= to include today
             planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).length;
    
    // Upcoming remaining tasks (only incomplete future plans)
    final upcomingRemaining = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      final todayNormalized = DateTime.tryParse(todayStr);
      if (planDateNormalized == null || todayNormalized == null) return false;
      return !plan.isCompleted && planDateNormalized.isAfter(todayNormalized); // Only incomplete future plans
    }).length;
    
    return {
      'today': todaysRemaining,
      'week': weeklyRemaining,
      'month': monthlyRemaining,
      'upcoming': upcomingRemaining,
    };
  }

  // Get task completion report: count Today, This Week, This Month
  Map<String, dynamic> getTaskCompletionReport() {
    // Use UserStats if available (from new API)
    if (userStats.value != null) {
      final tcr = userStats.value!.taskCompletionReport;
      return {
        'today': {
          'total': tcr.today.total,
          'completed': tcr.today.completed,
          'remaining': tcr.today.total - tcr.today.completed,
          'completion_rate': tcr.today.total > 0 
              ? (tcr.today.completed / tcr.today.total) * 100 
              : 0.0,
        },
        'week': {
          'total': tcr.week.total,
          'completed': tcr.week.completed,
          'remaining': tcr.week.total - tcr.week.completed,
          'completion_rate': tcr.week.total > 0 
              ? (tcr.week.completed / tcr.week.total) * 100 
              : 0.0,
        },
        'month': {
          'total': tcr.month.total,
          'completed': tcr.month.completed,
          'remaining': tcr.month.total - tcr.month.completed,
          'completion_rate': tcr.month.total > 0 
              ? (tcr.month.completed / tcr.month.total) * 100 
              : 0.0,
        },
        'upcoming': tcr.upcoming.total, // Use upcoming.total from backend
      };
    }
    
    // Calculate from daily plans (fallback - should match backend logic)
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T').first;
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 5)); // 6 days total
    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    
    // Today's tasks
    final todaysTasks = dailyPlans.where((plan) {
      final planDateStr = plan.planDate.split('T').first;
      return planDateStr == todayStr;
    }).toList();
    final todaysCompleted = todaysTasks.where((p) => p.isCompleted).length;
    final todaysIncomplete = todaysTasks.where((p) => !p.isCompleted).length;
    final todaysTotal = todaysCompleted + todaysIncomplete; // Fixed: total = completed + incomplete
    
    // Weekly tasks (6 days) - includes today's incomplete plans (>= todayStr)
    final weeklyCompletedPlans = <String>{};
    final weeklyIncompletePlans = <String>{};
    final todayNormalized = DateTime.tryParse(todayStr);
    for (final plan in dailyPlans) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) continue;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      if (planDateNormalized == null || todayNormalized == null) continue;
      // Changed from > to >= to include today's plans
      if ((planDateNormalized.isAfter(todayNormalized) || planDateNormalized.isAtSameMomentAs(todayNormalized)) &&
          planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
          planDate.isBefore(weekEnd.add(const Duration(days: 1)))) {
        if (plan.isCompleted) {
          weeklyCompletedPlans.add(plan.planDate);
        } else {
          weeklyIncompletePlans.add(plan.planDate);
        }
      }
    }
    final weeklyTotal = weeklyCompletedPlans.length + weeklyIncompletePlans.length; // Fixed: total = completed + incomplete
    final weeklyCompleted = weeklyCompletedPlans.length;
    
    // Monthly tasks - includes today's incomplete plans (>= todayStr)
    final monthlyCompletedPlans = <String>{};
    final monthlyIncompletePlans = <String>{};
    for (final plan in dailyPlans) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) continue;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      if (planDateNormalized == null || todayNormalized == null) continue;
      // Changed from > to >= to include today's plans
      if ((planDateNormalized.isAfter(todayNormalized) || planDateNormalized.isAtSameMomentAs(todayNormalized)) &&
          planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
          planDate.isBefore(monthEnd.add(const Duration(days: 1)))) {
        if (plan.isCompleted) {
          monthlyCompletedPlans.add(plan.planDate);
        } else {
          monthlyIncompletePlans.add(plan.planDate);
        }
      }
    }
    final monthlyTotal = monthlyCompletedPlans.length + monthlyIncompletePlans.length; // Fixed: total = completed + incomplete
    final monthlyCompleted = monthlyCompletedPlans.length;
    
    // Upcoming tasks - only incomplete future plans (!plan.is_completed && planDateStr > todayStr)
    final upcomingIncompletePlans = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      final planDateStr = plan.planDate.split('T').first;
      final planDateNormalized = DateTime.tryParse(planDateStr);
      if (planDateNormalized == null || todayNormalized == null) return false;
      return !plan.isCompleted && planDateNormalized.isAfter(todayNormalized); // Only incomplete future plans
    }).length;

    return {
      'today': {
        'total': todaysTotal,
        'completed': todaysCompleted,
        'remaining': todaysTotal - todaysCompleted,
        'completion_rate': todaysTotal > 0 ? (todaysCompleted / todaysTotal) * 100 : 0.0,
      },
      'week': {
        'total': weeklyTotal,
        'completed': weeklyCompleted,
        'remaining': weeklyTotal - weeklyCompleted,
        'completion_rate': weeklyTotal > 0 ? (weeklyCompleted / weeklyTotal) * 100 : 0.0,
      },
      'month': {
        'total': monthlyTotal,
        'completed': monthlyCompleted,
        'remaining': monthlyTotal - monthlyCompleted,
        'completion_rate': monthlyTotal > 0 ? (monthlyCompleted / monthlyTotal) * 100 : 0.0,
      },
      'upcoming': upcomingIncompletePlans, // Fixed: only incomplete future plans
    };
  }

  // Get total workouts (count of all individual workouts from all completed days)
  int getTotalWorkouts() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for total workouts');
      return 0;
    }
    
    // Count individual completed workouts from all days (not days)
    int totalWorkouts = 0;
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for total workouts');
      return 0;
    }
    
    // Count individual workouts from filtered dailyPlansRaw
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      
      // Count individual workouts in this plan
      dynamic exercisesDetails = planRaw['exercises_details'];
      List<Map<String, dynamic>> exercises = [];
      
      // Handle new structure: { workouts: [...], snapshots: [...] }
      if (exercisesDetails is List) {
        exercises = exercisesDetails.cast<Map<String, dynamic>>();
      } else if (exercisesDetails is Map<String, dynamic>) {
        if (exercisesDetails['workouts'] is List) {
          exercises = (exercisesDetails['workouts'] as List).cast<Map<String, dynamic>>();
        } else if (exercisesDetails['exercises'] is List) {
          exercises = (exercisesDetails['exercises'] as List).cast<Map<String, dynamic>>();
        } else if (exercisesDetails['items'] is List) {
          exercises = (exercisesDetails['items'] as List).cast<Map<String, dynamic>>();
        }
      } else if (exercisesDetails is String) {
        try {
          final parsed = jsonDecode(exercisesDetails);
          if (parsed is List) {
            exercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else if (parsed is Map<String, dynamic>) {
            if (parsed['workouts'] is List) {
              exercises = (parsed['workouts'] as List).cast<Map<String, dynamic>>();
            } else if (parsed['exercises'] is List) {
              exercises = (parsed['exercises'] as List).cast<Map<String, dynamic>>();
            } else if (parsed['items'] is List) {
              exercises = (parsed['items'] as List).cast<Map<String, dynamic>>();
            }
          }
        } catch (e) {
          print('⚠️ Stats - Failed to parse exercises_details in getTotalWorkouts: $e');
        }
      }
      
      // Count workouts that are completed
      for (final exercise in exercises) {
        if (exercise is Map<String, dynamic>) {
          final isWorkoutCompleted = exercise['is_completed'] as bool? ?? false;
          if (isWorkoutCompleted || isCompleted || !exercise.containsKey('is_completed')) {
            totalWorkouts++;
          }
        }
      }
    }
    
    // Also check parsed dailyPlans (fallback) - count workouts from items
    for (final plan in dailyPlans) {
      if (plan.isCompleted) {
        totalWorkouts += plan.items.length;
      }
    }
    
    // Also add local completions (each completion is a workout)
    totalWorkouts += _localCompletions.length;
    
    // Use UserStats as fallback if dailyPlansRaw is empty
    if (totalWorkouts == 0 && dailyPlansRaw.isEmpty && userStats.value != null) {
      // Estimate from total_workouts or monthly progress
      if (userStats.value!.totalWorkouts > 0) {
        print('📊 Stats - Total workouts (from UserStats): ${userStats.value!.totalWorkouts}');
        return userStats.value!.totalWorkouts;
      }
      // Estimate from monthly progress: completed days × 2 workouts per day
      final monthlyProgress = userStats.value!.monthlyProgress;
      if (monthlyProgress.completed > 0) {
        final estimated = monthlyProgress.completed * 2;
        print('📊 Stats - Total workouts (estimated from monthly progress: ${monthlyProgress.completed} days × 2 workouts): $estimated');
        return estimated;
      }
    }
    
    print('📊 Stats - Total workouts (individual count): $totalWorkouts');
    return totalWorkouts;
  }

  // Get total minutes (count total minutes of all days)
  int getTotalMinutes() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for total minutes');
      return 0;
    }
    
    // Use UserStats if available (but only if we have an active plan)
    if (userStats.value != null) {
      return userStats.value!.totalMinutes;
    }
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for total minutes');
      return 0;
    }
    
    // Sum minutes from filtered completed plans
    int totalMinutes = 0;
    
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      if (isCompleted) {
        totalMinutes += _extractMinutesFromPlanRaw(planRaw);
      }
    }
    
    return totalMinutes;
  }

  // Get longest streak (counts the days of completed workouts)
  int getLongestStreak() {
    // Check for active plan FIRST - if no active plan, return 0 immediately
    final activePlanIds = _getActivePlanSourceIds();
    if (activePlanIds == null) {
      print('🔍 Stats - No active plan, returning 0 for longest streak');
      return 0;
    }
    
    // Use UserStats if available
    // activePlanIds is already checked at the beginning, so it's not null here
    if (userStats.value != null) {
      return userStats.value!.longestStreak;
    }
    
    // Filter dailyPlansRaw to only include active plan's data
    final filteredPlans = _filterPlansByActivePlan(dailyPlansRaw);
    if (filteredPlans.isEmpty) {
      // No matching plans for active plan, return 0
      print('🔍 Stats - No matching plans for active plan, returning 0 for longest streak');
      return 0;
    }
    
    // Get unique completed dates (days) from filtered plans
    final completedDates = <String>{};
    
    // Use filtered dailyPlansRaw to get completed dates
    for (final planRaw in filteredPlans) {
      final isCompleted = planRaw['is_completed'] as bool? ?? false;
      final completedAt = planRaw['completed_at'] as String?;
      final planDate = planRaw['plan_date'] as String?;
      
      if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
        // Use completed_at date if available, otherwise use plan_date
        final dateStr = completedAt.split('T').first;
        completedDates.add(dateStr);
      } else if (isCompleted && planDate != null) {
        // Fallback to plan_date if completed_at is not available
        final dateStr = planDate.split('T').first;
        completedDates.add(dateStr);
      }
    }
    
    // Also check dailyPlans (fallback)
    for (final plan in dailyPlans) {
      if (plan.isCompleted) {
        completedDates.add(plan.planDate);
      }
    }
    
    // Also add local completions
    for (final completion in _localCompletions) {
      final completionDate = completion['date'] as String?;
      if (completionDate != null) {
        completedDates.add(completionDate);
      }
    }
    
    if (completedDates.isEmpty) return 0;
    
    // Sort dates in descending order (most recent first)
    final sortedDates = completedDates.toList()
      ..sort((a, b) => b.compareTo(a));
    
    int longestStreak = 0;
    int currentStreak = 0;
    DateTime? lastDate;
    
    for (final dateStr in sortedDates) {
      final planDate = DateTime.tryParse(dateStr);
      if (planDate == null) continue;
      
      if (lastDate == null) {
        currentStreak = 1;
        lastDate = planDate;
      } else {
        final daysDifference = lastDate.difference(planDate).inDays;
        if (daysDifference == 1) {
          // Consecutive day
          currentStreak++;
        } else if (daysDifference > 1) {
          // Streak broken - check if this is the longest
          if (currentStreak > longestStreak) {
            longestStreak = currentStreak;
          }
          currentStreak = 1;
        }
        lastDate = planDate;
      }
    }
    
    // Check if current streak is the longest
    if (currentStreak > longestStreak) {
      longestStreak = currentStreak;
    }
    
    return longestStreak;
  }

  // Get goal progress (assuming weekly goal of 5 workouts and monthly goal of 20 workouts)
  Map<String, dynamic> getGoalProgress() {
    final weeklyCompleted = getWeeklyCompletedWorkouts();
    final monthlyCompleted = getMonthlyCompletedWorkouts();
    final currentStreak = getCurrentStreak();
    
    const weeklyGoal = 5;
    const monthlyGoal = 20;
    const streakGoal = 30; // 30-day streak goal
    
    return {
      'weekly': {
        'completed': weeklyCompleted,
        'goal': weeklyGoal,
        'progress': (weeklyCompleted / weeklyGoal * 100).clamp(0.0, 100.0),
        'remaining': (weeklyGoal - weeklyCompleted).clamp(0, weeklyGoal),
        'achieved': weeklyCompleted >= weeklyGoal,
      },
      'monthly': {
        'completed': monthlyCompleted,
        'goal': monthlyGoal,
        'progress': (monthlyCompleted / monthlyGoal * 100).clamp(0.0, 100.0),
        'remaining': (monthlyGoal - monthlyCompleted).clamp(0, monthlyGoal),
        'achieved': monthlyCompleted >= monthlyGoal,
      },
      'streak': {
        'current': currentStreak,
        'goal': streakGoal,
        'progress': (currentStreak / streakGoal * 100).clamp(0.0, 100.0),
        'remaining': (streakGoal - currentStreak).clamp(0, streakGoal),
        'achieved': currentStreak >= streakGoal,
      },
    };
  }

  // Clear all cached data
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      
      await prefs.remove('cached_training_stats_user_$userId');
      await prefs.remove('cached_recent_workouts_user_$userId');
      
      _cachedStats.clear();
      _cachedRecentWorkouts.clear();
      
      print('✅ Stats - Cache cleared');
    } catch (e) {
      print('❌ Stats - Error clearing cache: $e');
    }
  }

  // Helper methods for converting between UserStats and TrainingStats

  /// Convert UserStats to TrainingStats for backward compatibility
  TrainingStats? _convertUserStatsToTrainingStats(UserStats? userStats) {
    if (userStats == null) return null;
    
    // Convert List<String> to List<Map<String, dynamic>> for recentWorkouts
    final recentWorkoutsAsMaps = userStats.recentWorkouts.map((workoutName) => {
      'name': workoutName,
      'workout_name': workoutName,
    }).toList();
    
    return TrainingStats(
      totalWorkoutsCompleted: userStats.totalWorkouts,
      totalMinutesSpent: userStats.totalMinutes,
      totalWeightLifted: 0.0, // Calculate from items if needed
      currentStreak: 0, // Calculate from dailyWorkouts if needed
      longestStreak: userStats.longestStreak,
      workoutsByCategory: {}, // Can be derived from items if needed
      recentWorkouts: recentWorkoutsAsMaps,
    );
  }

  /// Convert TrainingStats to UserStats (for legacy endpoint support)
  UserStats? _convertTrainingStatsToUserStats(TrainingStats? trainingStats) {
    if (trainingStats == null) return null;
    
    // Convert List<Map<String, dynamic>> to List<String> for recentWorkouts
    final recentWorkoutsAsStrings = trainingStats.recentWorkouts.map((workout) {
      return workout['workout_name']?.toString() ?? 
             workout['name']?.toString() ?? 
             workout.toString();
    }).toList();
    
    return UserStats(
      id: 0,
      userId: _profileController.user?.id ?? 0,
      dateUpdated: DateTime.now(),
      dailyWorkouts: {},
      totalWorkouts: trainingStats.totalWorkoutsCompleted,
      totalMinutes: trainingStats.totalMinutesSpent,
      longestStreak: trainingStats.longestStreak,
      recentWorkouts: recentWorkoutsAsStrings,
      weeklyProgress: WeeklyProgress(
        completed: 0,
        remaining: 0,
        total: 0,
        totalMinutes: 0,
        totalWorkouts: 0,
        batchNumber: 0,
        currentBatchSize: 12,
        nextBatchSize: 24,
      ),
      monthlyProgress: MonthlyProgress(
        completed: 0,
        remaining: 0,
        total: 0,
        completionRate: 0.0,
        dailyAvg: 0,
        daysPassed: 0,
        totalMinutes: 0,
        totalWorkouts: 0, // Explicitly set totalWorkouts to ensure all fields are present
        batchNumber: 0,
        batchSize: 30,
      ),
      remainingTasks: RemainingTasks(),
      taskCompletionReport: TaskCompletionReport(
        today: TaskStats(completed: 0, total: 0),
        week: TaskStats(completed: 0, total: 0),
        month: TaskStats(completed: 0, total: 0),
        upcoming: TaskStats(completed: 0, total: 0), // Added upcoming field
      ),
      items: [],
    );
  }

  /// Create default UserStats when no data is available
  /// NOTE: This method should not be used - we should always use real data from API
  /// Keeping it only for potential future use, but not calling it anywhere
  @Deprecated('Use real data from API instead of dummy data')
  UserStats _createDefaultUserStats() {
    // This method is deprecated - we should not create dummy data
    // Stats should always come from the API or be null
    return UserStats(
      id: 0,
      userId: _profileController.user?.id ?? 0,
      dateUpdated: DateTime.now(),
      dailyWorkouts: {},
      totalWorkouts: 0,
      totalMinutes: 0,
      longestStreak: 0,
      recentWorkouts: [],
      weeklyProgress: WeeklyProgress(
        completed: 0,
        remaining: 0,
        total: 0,
        totalMinutes: 0,
        totalWorkouts: 0,
        batchNumber: 0,
        currentBatchSize: 12,
        nextBatchSize: 24,
      ),
      monthlyProgress: MonthlyProgress(
        completed: 0,
        remaining: 0,
        total: 0,
        completionRate: 0.0,
        dailyAvg: 0,
        daysPassed: 0,
        totalMinutes: 0,
        totalWorkouts: 0, // Explicitly set totalWorkouts to ensure all fields are present
        batchNumber: 0,
        batchSize: 30,
      ),
      remainingTasks: RemainingTasks(),
      taskCompletionReport: TaskCompletionReport(
        today: TaskStats(completed: 0, total: 0),
        week: TaskStats(completed: 0, total: 0),
        month: TaskStats(completed: 0, total: 0),
        upcoming: TaskStats(completed: 0, total: 0), // Added upcoming field
      ),
      items: [],
    );
  }
}

