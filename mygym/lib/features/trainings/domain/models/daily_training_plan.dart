class DailyTrainingPlan {
  final int id;
  final int userId;
  final String planDate;
  final String planCategory;
  final String workoutName;
  final bool isCompleted;
  final List<DailyTrainingItem> items;

  DailyTrainingPlan({
    required this.id,
    required this.userId,
    required this.planDate,
    required this.planCategory,
    required this.workoutName,
    required this.isCompleted,
    required this.items,
  });

  factory DailyTrainingPlan.fromJson(Map<String, dynamic> json) {
    return DailyTrainingPlan(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      planDate: json['plan_date'] as String,
      planCategory: json['plan_category'] as String,
      workoutName: json['workout_name'] as String,
      isCompleted: json['is_completed'] as bool? ?? false,
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => DailyTrainingItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'plan_date': planDate,
      'plan_category': planCategory,
      'workout_name': workoutName,
      'is_completed': isCompleted,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  DailyTrainingPlan copyWith({
    int? id,
    int? userId,
    String? planDate,
    String? planCategory,
    String? workoutName,
    bool? isCompleted,
    List<DailyTrainingItem>? items,
  }) {
    return DailyTrainingPlan(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planDate: planDate ?? this.planDate,
      planCategory: planCategory ?? this.planCategory,
      workoutName: workoutName ?? this.workoutName,
      isCompleted: isCompleted ?? this.isCompleted,
      items: items ?? this.items,
    );
  }
}

class DailyTrainingItem {
  final int id;
  final String exerciseName;
  final int sets;
  final int reps;
  final double weightKg;
  final bool isCompleted;

  DailyTrainingItem({
    required this.id,
    required this.exerciseName,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.isCompleted,
  });

  factory DailyTrainingItem.fromJson(Map<String, dynamic> json) {
    return DailyTrainingItem(
      id: json['id'] as int,
      exerciseName: json['exercise_name'] as String,
      sets: json['sets'] as int,
      reps: json['reps'] as int,
      weightKg: (json['weight_kg'] as num).toDouble(),
      isCompleted: json['is_completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exercise_name': exerciseName,
      'sets': sets,
      'reps': reps,
      'weight_kg': weightKg,
      'is_completed': isCompleted,
    };
  }

  DailyTrainingItem copyWith({
    int? id,
    String? exerciseName,
    int? sets,
    int? reps,
    double? weightKg,
    bool? isCompleted,
  }) {
    return DailyTrainingItem(
      id: id ?? this.id,
      exerciseName: exerciseName ?? this.exerciseName,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weightKg: weightKg ?? this.weightKg,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class TrainingCompletionData {
  final int itemId;
  final int setsCompleted;
  final int repsCompleted;
  final double weightUsed;
  final int minutesSpent;
  final String? notes;

  TrainingCompletionData({
    required this.itemId,
    required this.setsCompleted,
    required this.repsCompleted,
    required this.weightUsed,
    required this.minutesSpent,
    this.notes,
  });

  factory TrainingCompletionData.fromJson(Map<String, dynamic> json) {
    return TrainingCompletionData(
      itemId: json['item_id'] as int,
      setsCompleted: json['sets_completed'] as int,
      repsCompleted: json['reps_completed'] as int,
      weightUsed: (json['weight_used'] as num).toDouble(),
      minutesSpent: json['minutes_spent'] as int,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'sets_completed': setsCompleted,
      'reps_completed': repsCompleted,
      'weight_used': weightUsed,
      'minutes_spent': minutesSpent,
      if (notes != null) 'notes': notes,
    };
  }
}

class TrainingStats {
  final int totalWorkoutsCompleted;
  final int totalMinutesSpent;
  final double totalWeightLifted;
  final int currentStreak;
  final int longestStreak;
  final Map<String, int> workoutsByCategory;
  final List<Map<String, dynamic>> recentWorkouts;

  TrainingStats({
    required this.totalWorkoutsCompleted,
    required this.totalMinutesSpent,
    required this.totalWeightLifted,
    required this.currentStreak,
    required this.longestStreak,
    required this.workoutsByCategory,
    required this.recentWorkouts,
  });

  factory TrainingStats.fromJson(Map<String, dynamic> json) {
    return TrainingStats(
      totalWorkoutsCompleted: json['total_workouts_completed'] as int? ?? 0,
      totalMinutesSpent: json['total_minutes_spent'] as int? ?? 0,
      totalWeightLifted: (json['total_weight_lifted'] as num?)?.toDouble() ?? 0.0,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      workoutsByCategory: Map<String, int>.from(json['workouts_by_category'] as Map<String, dynamic>? ?? {}),
      recentWorkouts: (json['recent_workouts'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_workouts_completed': totalWorkoutsCompleted,
      'total_minutes_spent': totalMinutesSpent,
      'total_weight_lifted': totalWeightLifted,
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'workouts_by_category': workoutsByCategory,
      'recent_workouts': recentWorkouts,
    };
  }
}
