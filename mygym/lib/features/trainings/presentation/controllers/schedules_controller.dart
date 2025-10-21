import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../stats/presentation/controllers/stats_controller.dart';
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
      
      // Fetch assigned training plans from assignments table (Schedules-specific)
      if (userId != null) {
        print('📋 Schedules - Fetching assigned training plans for user ID: $userId...');
        try {
          final assignmentsRes = await _manualService.getUserAssignments(userId);
          print('📋 Schedules - Assignments result: ${assignmentsRes.length} items');
          
          // Store assignments for Schedules tab only
          assignments.assignAll(assignmentsRes.map((e) => Map<String, dynamic>.from(e)));
          print('✅ Schedules - Assignments list updated: ${assignments.length} items');
        } catch (e) {
          print('❌ Schedules - Error fetching assignments: $e');
          // Fallback: try with user ID 2
          try {
            final fallbackRes = await _manualService.getUserAssignments(2);
            assignments.assignAll(fallbackRes.map((e) => Map<String, dynamic>.from(e)));
            print('✅ Schedules - Fallback assignments loaded: ${assignments.length} items');
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
  Future<Map<String, dynamic>> getAssignmentDetails(int assignmentId) async {
    return await _manualService.getAssignmentDetails(assignmentId);
  }

  void startSchedule(Map<String, dynamic> schedule) {
    final int? scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) return;
    
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
      _currentDay[planId.toString()] = currentDay + 1;
      _persistCurrentDayToCache(planId, currentDay + 1);
      
      // Clear completed workouts for next day
      for (String key in workoutKeys) {
        _workoutCompleted.remove(key);
        _workoutStarted.remove(key);
        _workoutRemainingMinutes.remove(key);
      }
      
      print('🔍 Moved to day ${currentDay + 1}, cleared workout states');
      
      // Force UI update
      refreshUI();
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

      final completionItem = DailyTrainingService.createCompletionItem(
        itemId: int.tryParse(workout['id']?.toString() ?? '0') ?? 0,
        setsCompleted: int.tryParse(workout['sets']?.toString() ?? '0') ?? 0,
        repsCompleted: int.tryParse(workout['reps']?.toString() ?? '0') ?? 0,
        weightUsed: double.tryParse(workout['weight_kg']?.toString() ?? '0') ?? 0.0,
        minutesSpent: actualMinutes,
        notes: 'Completed ${workoutName} (Day ${workoutDay + 1})',
      );

      // Try to submit to API first
      try {
        await _dailyTrainingService.submitCompletion(
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
            await _dailyTrainingService.submitCompletion(
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
      
      // Apply day-aware workout distribution logic
      if (workouts.isNotEmpty) {
        return _applyDayAwareWorkoutDistributionLogic(workouts, dayIndex);
      }
      
      return [];
    } catch (e) {
      return [];
    }
  }

  List<Map<String, dynamic>> _applyDayAwareWorkoutDistributionLogic(List<Map<String, dynamic>> workouts, int dayIndex) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 CONTROLLER DAY-AWARE DISTRIBUTION LOGIC - Day $dayIndex, Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Controller Workout $i: ${workout['name']} - ${workout['minutes']} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
      totalMinutes += minutes;
      print('🔍 Controller Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 CONTROLLER FINAL Total workout minutes: $totalMinutes');
    print('🔍 CONTROLLER FINAL Number of workouts: ${workouts.length}');
    
    // Day-aware workout distribution
    if (workouts.length >= 4) {
      // If we have 4 or more workouts, alternate between different pairs
      List<Map<String, dynamic>> dayWorkouts = [];
      
      if (dayIndex % 2 == 0) {
        // Even days (0, 2, 4...): Show first 2 workouts (Chest, Biceps)
        dayWorkouts = workouts.take(2).toList();
        print('🔍 CONTROLLER DAY $dayIndex (EVEN): Showing first 2 workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
      } else {
        // Odd days (1, 3, 5...): Show next 2 workouts (Triceps, Shoulders)
        if (workouts.length >= 4) {
          dayWorkouts = workouts.skip(2).take(2).toList();
          print('🔍 CONTROLLER DAY $dayIndex (ODD): Showing next 2 workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
        } else {
          // Fallback if we don't have enough workouts
          dayWorkouts = workouts.take(2).toList();
          print('🔍 CONTROLLER DAY $dayIndex (ODD FALLBACK): Showing first 2 workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
        }
      }
      
      return dayWorkouts;
    } else if (workouts.length > 2) {
      // If we have 3 workouts, alternate between different combinations
      List<Map<String, dynamic>> dayWorkouts = [];
      
      if (dayIndex % 2 == 0) {
        // Even days: Show first 2 workouts
        dayWorkouts = workouts.take(2).toList();
        print('🔍 CONTROLLER DAY $dayIndex (EVEN): Showing first 2 workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
      } else {
        // Odd days: Show last 2 workouts
        dayWorkouts = workouts.skip(1).take(2).toList();
        print('🔍 CONTROLLER DAY $dayIndex (ODD): Showing last 2 workouts: ${dayWorkouts.map((w) => w['name']).toList()}');
      }
      
      return dayWorkouts;
    } else {
      // If we have 2 or fewer workouts, show all workouts
      print('🔍 CONTROLLER DAY $dayIndex: Showing all ${workouts.length} workouts: ${workouts.map((w) => w['name']).toList()}');
      return workouts;
    }
  }

  List<Map<String, dynamic>> _applyWorkoutDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 CONTROLLER DISTRIBUTION LOGIC - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Controller Workout $i: ${workout['name']} - ${workout['minutes']} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
      totalMinutes += minutes;
      print('🔍 Controller Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 CONTROLLER FINAL Total workout minutes: $totalMinutes');
    print('🔍 CONTROLLER FINAL Number of workouts: ${workouts.length}');
    
    
    // Apply distribution logic
    if (totalMinutes > 80 && workouts.length > 2) {
      // If total minutes > 80 and we have more than 2 workouts, show only 2 workouts
      print('🔍 CONTROLLER ✅ APPLYING LOGIC: Total minutes ($totalMinutes) > 80, showing only 2 workouts');
      final filteredWorkouts = workouts.take(2).toList();
      print('🔍 CONTROLLER ✅ FILTERED: Showing ${filteredWorkouts.length} workouts: ${filteredWorkouts.map((w) => w['name']).toList()}');
      return filteredWorkouts;
    } else {
      // If total minutes <= 80 or we have 2 or fewer workouts, show all workouts
      print('🔍 CONTROLLER ✅ APPLYING LOGIC: Total minutes ($totalMinutes) <= 80 or <= 2 workouts, showing all ${workouts.length} workouts');
      return workouts;
    }
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
    _currentDay.refresh();
    _workoutStarted.refresh();
    _workoutCompleted.refresh();
    _workoutRemainingMinutes.refresh();
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
        
        final completionItem = DailyTrainingService.createCompletionItem(
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
        // Submit to daily training API
        await _dailyTrainingService.submitCompletion(
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
}
