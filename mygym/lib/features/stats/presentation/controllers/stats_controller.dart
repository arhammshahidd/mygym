import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../trainings/data/services/daily_training_service.dart';
import '../../../trainings/domain/models/daily_training_plan.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../../shared/services/realtime_service.dart';
import '../../../auth/data/services/auth_service.dart';

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

      // Fetch training statistics
      try {
        print('📊 Stats - Fetching training statistics...');
        final statsData = await _dailyTrainingService.getTrainingStats();
        print('📊 Stats - Training stats result: $statsData');
        
        trainingStats.value = TrainingStats.fromJson(statsData);
        _cachedStats.assignAll(statsData);
        print('✅ Stats - Training stats updated');
      } catch (e) {
        print('⚠️ Stats - Failed to load training stats: $e');
        // Use cached data if available
        if (_cachedStats.isNotEmpty) {
          trainingStats.value = TrainingStats.fromJson(_cachedStats);
        }
      }

      // Fetch recent daily plans
      try {
        print('📊 Stats - Fetching recent daily plans...');
        final plansData = await _dailyTrainingService.getDailyPlans();
        print('📊 Stats - Daily plans result: ${plansData.length} items');
        
        dailyPlans.assignAll(plansData.map((plan) => DailyTrainingPlan.fromJson(plan)));
        print('✅ Stats - Daily plans updated: ${dailyPlans.length} items');
      } catch (e) {
        print('⚠️ Stats - Failed to load daily plans: $e');
        dailyPlans.clear();
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

  Future<void> refreshStats() async {
    print('🔄 Stats - Refreshing stats data...');
    await _loadLocalCompletions(); // Reload local completions first
    await loadStatsData();
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

  // Get completed workouts count for today
  int getTodaysCompletedWorkouts() {
    final today = DateTime.now().toIso8601String().split('T').first;
    final apiCompleted = dailyPlans.where((plan) => 
      plan.planDate == today && plan.isCompleted
    ).length;
    
    // Also count locally stored completions for today
    final localCompleted = _getLocalCompletionsForDate(today).length;
    
    return apiCompleted + localCompleted;
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

  // Get total workouts completed this week
  int getWeeklyCompletedWorkouts() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    
    final apiCompleted = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return plan.isCompleted && 
             planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).length;

    // Count local completions for this week
    final localCompleted = _localCompletions.where((completion) {
      final completionDate = DateTime.tryParse(completion['date'] as String? ?? '');
      if (completionDate == null) return false;
      return completionDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             completionDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).length;
    
    return apiCompleted + localCompleted;
  }

  // Get total workouts completed this month
  int getMonthlyCompletedWorkouts() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    
    final apiCompleted = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return plan.isCompleted && 
             planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).length;

    // Count local completions for this month
    final localCompleted = _localCompletions.where((completion) {
      final completionDate = DateTime.tryParse(completion['date'] as String? ?? '');
      if (completionDate == null) return false;
      return completionDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             completionDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).length;
    
    return apiCompleted + localCompleted;
  }

  // Get weekly progress details
  Map<String, dynamic> getWeeklyProgress() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    
    final completedPlans = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return plan.isCompleted && 
             planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList();

    final incompletePlans = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && 
             planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList();

    // Minutes per item not tracked in DailyTrainingItem model; sum as 0 for now.
    final totalMinutes = completedPlans.fold<int>(0, (sum, plan) {
      return sum + 0;
    });

    final totalWeight = completedPlans.fold<double>(0.0, (sum, plan) {
      return sum + plan.items.fold<double>(0.0, (itemSum, item) {
        return itemSum + (item.weightKg * item.sets * item.reps);
      });
    });

    return {
      'completed_workouts': completedPlans.length,
      'incomplete_workouts': incompletePlans.length,
      'total_planned_workouts': completedPlans.length + incompletePlans.length,
      'completion_rate': completedPlans.length + incompletePlans.length > 0 
          ? (completedPlans.length / (completedPlans.length + incompletePlans.length)) * 100 
          : 0.0,
      'total_minutes': totalMinutes,
      'total_weight_lifted': totalWeight,
      'week_start': weekStart.toIso8601String().split('T').first,
      'week_end': weekEnd.toIso8601String().split('T').first,
      'incomplete_plans': incompletePlans,
    };
  }

  // Get monthly progress details
  Map<String, dynamic> getMonthlyProgress() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    
    final completedPlans = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return plan.isCompleted && 
             planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).toList();

    final incompletePlans = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return !plan.isCompleted && 
             planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(monthEnd.add(const Duration(days: 1)));
    }).toList();

    // Minutes per item not tracked in DailyTrainingItem model; sum as 0 for now.
    final totalMinutes = completedPlans.fold<int>(0, (sum, plan) {
      return sum + 0;
    });

    final totalWeight = completedPlans.fold<double>(0.0, (sum, plan) {
      return sum + plan.items.fold<double>(0.0, (itemSum, item) {
        return itemSum + (item.weightKg * item.sets * item.reps);
      });
    });

    // Calculate daily average
    final daysInMonth = monthEnd.day;
    final daysPassed = now.day;
    final dailyAverage = daysPassed > 0 ? completedPlans.length / daysPassed : 0.0;

    return {
      'completed_workouts': completedPlans.length,
      'incomplete_workouts': incompletePlans.length,
      'total_planned_workouts': completedPlans.length + incompletePlans.length,
      'completion_rate': completedPlans.length + incompletePlans.length > 0 
          ? (completedPlans.length / (completedPlans.length + incompletePlans.length)) * 100 
          : 0.0,
      'total_minutes': totalMinutes,
      'total_weight_lifted': totalWeight,
      'daily_average': dailyAverage,
      'days_passed': daysPassed,
      'days_in_month': daysInMonth,
      'month_start': monthStart.toIso8601String().split('T').first,
      'month_end': monthEnd.toIso8601String().split('T').first,
      'incomplete_plans': incompletePlans,
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

  // Get recent workouts (last 7 days)
  List<DailyTrainingPlan> getRecentWorkouts({int days = 7}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    return dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return plan.isCompleted && planDate.isAfter(cutoffDate);
    }).toList()
    ..sort((a, b) => b.planDate.compareTo(a.planDate));
  }

  // Get current streak
  int getCurrentStreak() {
    final sortedPlans = dailyPlans.where((plan) => plan.isCompleted).toList()
      ..sort((a, b) => b.planDate.compareTo(a.planDate));
    
    if (sortedPlans.isEmpty) return 0;
    
    int streak = 0;
    DateTime? lastDate;
    
    for (final plan in sortedPlans) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) continue;
      
      if (lastDate == null) {
        // First completed workout
        streak = 1;
        lastDate = planDate;
      } else {
        final daysDifference = lastDate.difference(planDate).inDays;
        if (daysDifference == 1) {
          // Consecutive day
          streak++;
          lastDate = planDate;
        } else if (daysDifference > 1) {
          // Streak broken
          break;
        }
      }
    }
    
    return streak;
  }

  // Get remaining tasks for today
  List<DailyTrainingPlan> getTodaysRemainingTasks() {
    final today = DateTime.now().toIso8601String().split('T').first;
    return dailyPlans.where((plan) => 
      plan.planDate == today && !plan.isCompleted
    ).toList();
  }

  // Get remaining tasks for this week
  List<DailyTrainingPlan> getWeeklyRemainingTasks() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    
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

  // Get task completion report
  Map<String, dynamic> getTaskCompletionReport() {
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month, 1);
    
    final todaysTasks = dailyPlans.where((plan) => plan.planDate == today.toIso8601String().split('T').first).toList();
    final weeklyTasks = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return planDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(weekStart.add(const Duration(days: 7)));
    }).toList();
    final monthlyTasks = dailyPlans.where((plan) {
      final planDate = DateTime.tryParse(plan.planDate);
      if (planDate == null) return false;
      return planDate.isAfter(monthStart.subtract(const Duration(days: 1))) &&
             planDate.isBefore(DateTime(today.year, today.month + 1, 0));
    }).toList();

    return {
      'today': {
        'total': todaysTasks.length,
        'completed': todaysTasks.where((p) => p.isCompleted).length,
        'remaining': todaysTasks.where((p) => !p.isCompleted).length,
        'completion_rate': todaysTasks.isNotEmpty ? (todaysTasks.where((p) => p.isCompleted).length / todaysTasks.length) * 100 : 0.0,
      },
      'week': {
        'total': weeklyTasks.length,
        'completed': weeklyTasks.where((p) => p.isCompleted).length,
        'remaining': weeklyTasks.where((p) => !p.isCompleted).length,
        'completion_rate': weeklyTasks.isNotEmpty ? (weeklyTasks.where((p) => p.isCompleted).length / weeklyTasks.length) * 100 : 0.0,
      },
      'month': {
        'total': monthlyTasks.length,
        'completed': monthlyTasks.where((p) => p.isCompleted).length,
        'remaining': monthlyTasks.where((p) => !p.isCompleted).length,
        'completion_rate': monthlyTasks.isNotEmpty ? (monthlyTasks.where((p) => p.isCompleted).length / monthlyTasks.length) * 100 : 0.0,
      },
      'overdue': getOverdueTasks().length,
      'upcoming': getUpcomingTasks().length,
    };
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
}
