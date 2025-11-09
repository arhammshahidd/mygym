import 'dart:convert';

/// User statistics model based on the daily_training_plans table stats record
class UserStats {
  final int id;
  final int userId;
  final DateTime dateUpdated;
  final Map<String, List<String>> dailyWorkouts;
  final int totalWorkouts;
  final int totalMinutes;
  final int longestStreak;
  final List<String> recentWorkouts;
  final WeeklyProgress weeklyProgress;
  final MonthlyProgress monthlyProgress;
  final RemainingTasks remainingTasks;
  final TaskCompletionReport taskCompletionReport;
  final List<ExerciseDetail> items;

  UserStats({
    required this.id,
    required this.userId,
    required this.dateUpdated,
    required this.dailyWorkouts,
    required this.totalWorkouts,
    required this.totalMinutes,
    required this.longestStreak,
    required this.recentWorkouts,
    required this.weeklyProgress,
    required this.monthlyProgress,
    required this.remainingTasks,
    required this.taskCompletionReport,
    this.items = const [],
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    // Backend now sends daily_workouts with structure: {"date": {"workouts": [...], "count": N}}
    // Handle both old format: {"date": ["workout1", "workout2"]}
    // and new format: {"date": {"workouts": ["workout1", "workout2"], "count": 2}}
    final dailyWorkoutsMap = <String, List<String>>{};
    final dailyWorkoutsRaw = json['daily_workouts'] as Map<String, dynamic>? ?? {};
    
    for (final entry in dailyWorkoutsRaw.entries) {
      final date = entry.key;
      final value = entry.value;
      
      if (value is List) {
        // Old format: {"date": ["workout1", "workout2"]}
        dailyWorkoutsMap[date] = List<String>.from(value);
      } else if (value is Map<String, dynamic>) {
        // New format: {"date": {"workouts": ["workout1", "workout2"], "count": 2}}
        final workouts = value['workouts'] as List?;
        if (workouts != null) {
          dailyWorkoutsMap[date] = List<String>.from(workouts);
        }
      }
    }
    
    return UserStats(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      dateUpdated: DateTime.parse(json['date_updated'] as String),
      dailyWorkouts: dailyWorkoutsMap,
      totalWorkouts: json['total_workouts'] as int? ?? 0,
      totalMinutes: json['total_minutes'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      recentWorkouts: List<String>.from(json['recent_workouts'] as List? ?? []),
      weeklyProgress: WeeklyProgress.fromJson(json['weekly_progress'] as Map<String, dynamic>? ?? {}),
      monthlyProgress: MonthlyProgress.fromJson(json['monthly_progress'] as Map<String, dynamic>? ?? {}),
      remainingTasks: RemainingTasks.fromJson(json['remaining_tasks'] as Map<String, dynamic>? ?? {}),
      taskCompletionReport: TaskCompletionReport.fromJson(
        json['task_completion_report'] as Map<String, dynamic>? ?? {},
      ),
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => ExerciseDetail.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date_updated': dateUpdated.toIso8601String(),
      'daily_workouts': dailyWorkouts,
      'total_workouts': totalWorkouts,
      'total_minutes': totalMinutes,
      'longest_streak': longestStreak,
      'recent_workouts': recentWorkouts,
      'weekly_progress': weeklyProgress.toJson(),
      'monthly_progress': monthlyProgress.toJson(),
      'remaining_tasks': remainingTasks.toJson(),
      'task_completion_report': taskCompletionReport.toJson(),
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class WeeklyProgress {
  final int completed;
  final int remaining;
  final int total;
  final int totalMinutes;
  final int totalWorkouts;
  final int batchNumber;
  final int currentBatchSize;
  final int nextBatchSize;

  WeeklyProgress({
    required this.completed,
    required this.remaining,
    required this.total,
    required this.totalMinutes,
    required this.totalWorkouts,
    required this.batchNumber,
    required this.currentBatchSize,
    required this.nextBatchSize,
  });

  factory WeeklyProgress.fromJson(Map<String, dynamic> json) {
    return WeeklyProgress(
      completed: json['completed'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      totalMinutes: json['total_minutes'] as int? ?? 0,
      totalWorkouts: json['total_workouts'] as int? ?? 0,
      batchNumber: json['batch_number'] as int? ?? 0,
      currentBatchSize: json['current_batch_size'] as int? ?? 12,
      nextBatchSize: json['next_batch_size'] as int? ?? 24,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'remaining': remaining,
      'total': total,
      'total_minutes': totalMinutes,
      'total_workouts': totalWorkouts,
      'batch_number': batchNumber,
      'current_batch_size': currentBatchSize,
      'next_batch_size': nextBatchSize,
    };
  }
}

class MonthlyProgress {
  final int completed;
  final int remaining;
  final int total;
  final double completionRate;
  final int dailyAvg;
  final int daysPassed;
  final int totalMinutes;
  final int totalWorkouts; // New field: individual workouts count
  final int batchNumber;
  final int batchSize;

  MonthlyProgress({
    required this.completed,
    required this.remaining,
    required this.total,
    required this.completionRate,
    required this.dailyAvg,
    required this.daysPassed,
    required this.totalMinutes,
    this.totalWorkouts = 0, // Default to 0 if not provided
    required this.batchNumber,
    required this.batchSize,
  });

  factory MonthlyProgress.fromJson(Map<String, dynamic> json) {
    return MonthlyProgress(
      completed: json['completed'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0.0,
      dailyAvg: json['daily_avg'] as int? ?? 0,
      daysPassed: json['days_passed'] as int? ?? 0,
      totalMinutes: json['total_minutes'] as int? ?? 0,
      totalWorkouts: json['total_workouts'] as int? ?? 0, // New field
      batchNumber: json['batch_number'] as int? ?? 0,
      batchSize: json['batch_size'] as int? ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'remaining': remaining,
      'total': total,
      'completion_rate': completionRate,
      'daily_avg': dailyAvg,
      'days_passed': daysPassed,
      'total_minutes': totalMinutes,
      'total_workouts': totalWorkouts, // New field
      'batch_number': batchNumber,
      'batch_size': batchSize,
    };
  }
}

class RemainingTasks {
  final List<String> today;
  final List<String> weekly;
  final List<String> monthly;
  final List<String> upcoming;

  RemainingTasks({
    this.today = const [],
    this.weekly = const [],
    this.monthly = const [],
    this.upcoming = const [],
  });

  factory RemainingTasks.fromJson(Map<String, dynamic> json) {
    return RemainingTasks(
      today: List<String>.from(json['today'] as List? ?? []),
      weekly: List<String>.from(json['weekly'] as List? ?? []),
      monthly: List<String>.from(json['monthly'] as List? ?? []),
      upcoming: List<String>.from(json['upcoming'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'today': today,
      'weekly': weekly,
      'monthly': monthly,
      'upcoming': upcoming,
    };
  }
}

class TaskCompletionReport {
  final TaskStats today;
  final TaskStats week;
  final TaskStats month;
  final TaskStats upcoming; // Added upcoming field

  TaskCompletionReport({
    required this.today,
    required this.week,
    required this.month,
    required this.upcoming, // Added upcoming field
  });

  factory TaskCompletionReport.fromJson(Map<String, dynamic> json) {
    return TaskCompletionReport(
      today: TaskStats.fromJson(json['today'] as Map<String, dynamic>? ?? {}),
      week: TaskStats.fromJson(json['week'] as Map<String, dynamic>? ?? {}),
      month: TaskStats.fromJson(json['month'] as Map<String, dynamic>? ?? {}),
      upcoming: TaskStats.fromJson(json['upcoming'] as Map<String, dynamic>? ?? {}), // Added upcoming field
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'today': today.toJson(),
      'week': week.toJson(),
      'month': month.toJson(),
      'upcoming': upcoming.toJson(), // Added upcoming field
    };
  }
}

class TaskStats {
  final int completed;
  final int total;
  final int? totalWorkouts; // New field: individual workouts count (for today)

  TaskStats({
    required this.completed,
    required this.total,
    this.totalWorkouts, // Optional field
  });

  factory TaskStats.fromJson(Map<String, dynamic> json) {
    return TaskStats(
      completed: json['completed'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      totalWorkouts: json['total_workouts'] as int?, // New field
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'total': total,
      if (totalWorkouts != null) 'total_workouts': totalWorkouts,
    };
  }
}

class ExerciseDetail {
  final int? id;
  final int? itemId;
  final String? exerciseName;
  final String? workoutName;
  final String? name;
  final int sets;
  final int reps;
  final double weightKg;
  final double? weightMinKg;
  final double? weightMaxKg;
  final int minutes;
  final int? trainingMinutes;
  final String? exerciseType;
  final String? exerciseTypes;
  final String? notes;
  final bool isCompleted;
  final String? completedAt;

  ExerciseDetail({
    this.id,
    this.itemId,
    this.exerciseName,
    this.workoutName,
    this.name,
    this.sets = 0,
    this.reps = 0,
    this.weightKg = 0,
    this.weightMinKg,
    this.weightMaxKg,
    this.minutes = 0,
    this.trainingMinutes,
    this.exerciseType,
    this.exerciseTypes,
    this.notes,
    this.isCompleted = false,
    this.completedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'exercise_name': exerciseName ?? name ?? workoutName,
      'workout_name': workoutName,
      'name': name ?? exerciseName,
      'sets': sets,
      'reps': reps,
      'weight_kg': weightKg,
      if (weightMinKg != null) 'weight_min_kg': weightMinKg,
      if (weightMaxKg != null) 'weight_max_kg': weightMaxKg,
      'minutes': minutes,
      'training_minutes': trainingMinutes ?? minutes,
      'exercise_type': exerciseType ?? exerciseTypes,
      if (notes != null) 'notes': notes,
      'is_completed': isCompleted,
      if (completedAt != null) 'completed_at': completedAt,
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
    };
  }

  factory ExerciseDetail.fromJson(Map<String, dynamic> json) {
    return ExerciseDetail(
      id: json['id'] as int?,
      itemId: json['item_id'] as int?,
      exerciseName: json['exercise_name'] ?? json['name'],
      workoutName: json['workout_name'],
      name: json['name'] ?? json['exercise_name'],
      sets: json['sets'] as int? ?? 0,
      reps: json['reps'] as int? ?? 0,
      weightKg: ((json['weight_kg'] ?? 0) as num).toDouble(),
      weightMinKg: json['weight_min_kg']?.toDouble(),
      weightMaxKg: json['weight_max_kg']?.toDouble(),
      minutes: json['minutes'] ?? json['training_minutes'] ?? 0,
      trainingMinutes: json['training_minutes'] ?? json['minutes'],
      exerciseType: json['exercise_type'] ?? json['exercise_types'],
      exerciseTypes: json['exercise_types'] ?? json['exercise_type'],
      notes: json['notes'],
      isCompleted: json['is_completed'] as bool? ?? false,
      completedAt: json['completed_at'],
    );
  }
}

