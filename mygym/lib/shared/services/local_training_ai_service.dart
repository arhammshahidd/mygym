import 'dart:math';

class LocalTrainingAIService {
  Future<Map<String, dynamic>> generateTrainingPlanJson({
    required int userId,
    required String exercisePlan,
    required String startDate,
    required String endDate,
    required int age,
    required int heightCm,
    required int weightKg,
    required String gender,
    required String futureGoal,
  }) async {
    print('🏋️ LOCAL AI: Generating training plan for user $userId');
    print('🎯 Goal: $futureGoal, Plan: $exercisePlan, Age: $age, Weight: ${weightKg}kg, Height: ${heightCm}cm');

    // Calculate realistic plan duration based on goal and experience level
    int planDays = _calculatePlanDuration(futureGoal, exercisePlan);
    int workoutsPerWeek = _calculateWorkoutsPerWeek(futureGoal, exercisePlan);
    int totalWorkouts = (planDays / 7 * workoutsPerWeek).round();
    int totalMinutes = _calculateTotalMinutes(totalWorkouts, futureGoal);

    print('📅 Plan Duration: $planDays days, $workoutsPerWeek workouts/week, $totalWorkouts total workouts, $totalMinutes minutes');

    // Generate realistic workout items
    final List<Map<String, dynamic>> items = _generateWorkoutItems(
      exercisePlan: exercisePlan,
      futureGoal: futureGoal,
      totalWorkouts: totalWorkouts,
      totalMinutes: totalMinutes,
      age: age,
      weightKg: weightKg,
      gender: gender,
    );

    print('✅ LOCAL AI: Generated ${items.length} workout items');

    return {
      'user_id': userId,
      'start_date': startDate,
      'end_date': endDate,
      'exercise_plan': exercisePlan,
      'total_workouts': totalWorkouts,
      'total_training_minutes': totalMinutes,
      'items': items,
    };
  }

  int _calculatePlanDuration(String futureGoal, String exercisePlan) {
    final goal = futureGoal.toLowerCase();
    final plan = exercisePlan.toLowerCase();

    // Base duration on goal complexity
    if (goal.contains('beginner') || goal.contains('start')) {
      return 28; // 4 weeks for beginners
    } else if (goal.contains('weight loss') || goal.contains('lose weight')) {
      return 42; // 6 weeks for weight loss
    } else if (goal.contains('muscle') || goal.contains('strength') || goal.contains('build')) {
      return 56; // 8 weeks for muscle building
    } else if (goal.contains('endurance') || goal.contains('cardio')) {
      return 35; // 5 weeks for endurance
    } else if (goal.contains('advanced') || goal.contains('expert')) {
      return 70; // 10 weeks for advanced
    }

    // Default based on plan type
    switch (plan) {
      case 'strength':
      case 'muscle building':
        return 56; // 8 weeks
      case 'weight loss':
      case 'fat loss':
        return 42; // 6 weeks
      case 'cardio':
      case 'endurance':
        return 35; // 5 weeks
      case 'beginner':
        return 28; // 4 weeks
      default:
        return 42; // 6 weeks default
    }
  }

  int _calculateWorkoutsPerWeek(String futureGoal, String exercisePlan) {
    final goal = futureGoal.toLowerCase();
    final plan = exercisePlan.toLowerCase();

    if (goal.contains('beginner') || goal.contains('start')) {
      return 3; // 3 days for beginners
    } else if (goal.contains('weight loss') || goal.contains('lose weight')) {
      return 5; // 5 days for weight loss (more cardio)
    } else if (goal.contains('muscle') || goal.contains('strength')) {
      return 4; // 4 days for muscle building
    } else if (goal.contains('endurance') || goal.contains('cardio')) {
      return 6; // 6 days for endurance
    } else if (goal.contains('advanced') || goal.contains('expert')) {
      return 5; // 5 days for advanced
    }

    // Default based on plan type
    switch (plan) {
      case 'strength':
      case 'muscle building':
        return 4;
      case 'weight loss':
      case 'fat loss':
        return 5;
      case 'cardio':
      case 'endurance':
        return 6;
      case 'beginner':
        return 3;
      default:
        return 4;
    }
  }

  int _calculateTotalMinutes(int totalWorkouts, String futureGoal) {
    final goal = futureGoal.toLowerCase();
    
    int minutesPerWorkout;
    if (goal.contains('beginner')) {
      minutesPerWorkout = 30; // Shorter for beginners
    } else if (goal.contains('endurance') || goal.contains('cardio')) {
      minutesPerWorkout = 60; // Longer for cardio
    } else if (goal.contains('advanced')) {
      minutesPerWorkout = 90; // Longer for advanced
    } else {
      minutesPerWorkout = 45; // Standard duration
    }

    return totalWorkouts * minutesPerWorkout;
  }

  List<Map<String, dynamic>> _generateWorkoutItems({
    required String exercisePlan,
    required String futureGoal,
    required int totalWorkouts,
    required int totalMinutes,
    required int age,
    required int weightKg,
    required String gender,
  }) {
    final List<Map<String, dynamic>> items = [];
    final random = Random();

    // Define workout categories based on plan type
    final Map<String, List<Map<String, dynamic>>> workoutCategories = _getWorkoutCategories(
      exercisePlan: exercisePlan,
      futureGoal: futureGoal,
      age: age,
      weightKg: weightKg,
      gender: gender,
    );

    // Distribute workouts across categories
    final categoryKeys = workoutCategories.keys.toList();
    int workoutsGenerated = 0;

    while (workoutsGenerated < totalWorkouts) {
      for (String category in categoryKeys) {
        if (workoutsGenerated >= totalWorkouts) break;

        final workouts = workoutCategories[category]!;
        final selectedWorkout = workouts[random.nextInt(workouts.length)];
        
        // Calculate realistic sets, reps, and weight based on user profile
        final workout = _calculateWorkoutParameters(
          baseWorkout: selectedWorkout,
          age: age,
          weightKg: weightKg,
          gender: gender,
          futureGoal: futureGoal,
        );

        items.add(workout);
        workoutsGenerated++;
      }
    }

    return items;
  }

  Map<String, List<Map<String, dynamic>>> _getWorkoutCategories({
    required String exercisePlan,
    required String futureGoal,
    required int age,
    required int weightKg,
    required String gender,
  }) {
    final plan = exercisePlan.toLowerCase();
    final goal = futureGoal.toLowerCase();

    if (plan.contains('strength') || plan.contains('muscle') || goal.contains('muscle') || goal.contains('strength')) {
      return {
        'Upper Body': [
          {'name': 'Bench Press', 'exercise_types': 'Strength Training'},
          {'name': 'Pull-ups', 'exercise_types': 'Strength Training'},
          {'name': 'Overhead Press', 'exercise_types': 'Strength Training'},
          {'name': 'Bent-over Rows', 'exercise_types': 'Strength Training'},
          {'name': 'Dumbbell Flyes', 'exercise_types': 'Strength Training'},
          {'name': 'Lat Pulldowns', 'exercise_types': 'Strength Training'},
        ],
        'Lower Body': [
          {'name': 'Squats', 'exercise_types': 'Strength Training'},
          {'name': 'Deadlifts', 'exercise_types': 'Strength Training'},
          {'name': 'Lunges', 'exercise_types': 'Strength Training'},
          {'name': 'Leg Press', 'exercise_types': 'Strength Training'},
          {'name': 'Calf Raises', 'exercise_types': 'Strength Training'},
          {'name': 'Romanian Deadlifts', 'exercise_types': 'Strength Training'},
        ],
        'Core': [
          {'name': 'Plank', 'exercise_types': 'Core Training'},
          {'name': 'Russian Twists', 'exercise_types': 'Core Training'},
          {'name': 'Mountain Climbers', 'exercise_types': 'Core Training'},
          {'name': 'Dead Bug', 'exercise_types': 'Core Training'},
        ],
      };
    } else if (plan.contains('cardio') || plan.contains('endurance') || goal.contains('endurance') || goal.contains('cardio')) {
      return {
        'Cardio': [
          {'name': 'Running', 'exercise_types': 'Cardio'},
          {'name': 'Cycling', 'exercise_types': 'Cardio'},
          {'name': 'Swimming', 'exercise_types': 'Cardio'},
          {'name': 'Rowing', 'exercise_types': 'Cardio'},
          {'name': 'Elliptical', 'exercise_types': 'Cardio'},
          {'name': 'Jump Rope', 'exercise_types': 'Cardio'},
        ],
        'HIIT': [
          {'name': 'HIIT Circuit', 'exercise_types': 'HIIT'},
          {'name': 'Tabata Training', 'exercise_types': 'HIIT'},
          {'name': 'Burpees', 'exercise_types': 'HIIT'},
          {'name': 'High Knees', 'exercise_types': 'HIIT'},
          {'name': 'Jumping Jacks', 'exercise_types': 'HIIT'},
        ],
      };
    } else if (plan.contains('weight loss') || plan.contains('fat loss') || goal.contains('weight loss') || goal.contains('lose weight')) {
      return {
        'Full Body': [
          {'name': 'Full Body Circuit', 'exercise_types': 'Circuit Training'},
          {'name': 'Bodyweight HIIT', 'exercise_types': 'HIIT'},
          {'name': 'Kettlebell Swings', 'exercise_types': 'Functional Training'},
          {'name': 'Battle Ropes', 'exercise_types': 'Cardio'},
        ],
        'Cardio': [
          {'name': 'Treadmill Running', 'exercise_types': 'Cardio'},
          {'name': 'Stationary Bike', 'exercise_types': 'Cardio'},
          {'name': 'Stair Climbing', 'exercise_types': 'Cardio'},
          {'name': 'Rowing Machine', 'exercise_types': 'Cardio'},
        ],
        'Strength': [
          {'name': 'Compound Movements', 'exercise_types': 'Strength Training'},
          {'name': 'Functional Training', 'exercise_types': 'Functional Training'},
          {'name': 'Resistance Bands', 'exercise_types': 'Strength Training'},
        ],
      };
    } else {
      // Beginner/General fitness
      return {
        'Full Body': [
          {'name': 'Full Body Workout', 'exercise_types': 'Full Body'},
          {'name': 'Bodyweight Training', 'exercise_types': 'Bodyweight'},
          {'name': 'Basic Strength', 'exercise_types': 'Strength Training'},
        ],
        'Cardio': [
          {'name': 'Light Cardio', 'exercise_types': 'Cardio'},
          {'name': 'Walking', 'exercise_types': 'Cardio'},
          {'name': 'Low Impact Cardio', 'exercise_types': 'Cardio'},
        ],
        'Flexibility': [
          {'name': 'Stretching', 'exercise_types': 'Flexibility'},
          {'name': 'Yoga', 'exercise_types': 'Flexibility'},
          {'name': 'Mobility Work', 'exercise_types': 'Flexibility'},
        ],
      };
    }
  }

  Map<String, dynamic> _calculateWorkoutParameters({
    required Map<String, dynamic> baseWorkout,
    required int age,
    required int weightKg,
    required String gender,
    required String futureGoal,
  }) {
    final random = Random();
    final goal = futureGoal.toLowerCase();

    // Calculate base weight based on user profile
    double baseWeight = weightKg * 0.5; // Start with 50% of body weight
    if (gender.toLowerCase() == 'female') {
      baseWeight *= 0.8; // Adjust for gender
    }
    if (age > 50) {
      baseWeight *= 0.9; // Adjust for age
    }

    // Calculate sets and reps based on goal
    int sets, reps;
    if (goal.contains('muscle') || goal.contains('strength')) {
      sets = 3 + random.nextInt(2); // 3-4 sets
      reps = 8 + random.nextInt(5); // 8-12 reps
    } else if (goal.contains('endurance') || goal.contains('cardio')) {
      sets = 2 + random.nextInt(2); // 2-3 sets
      reps = 15 + random.nextInt(10); // 15-24 reps
    } else if (goal.contains('weight loss') || goal.contains('lose weight')) {
      sets = 3 + random.nextInt(2); // 3-4 sets
      reps = 12 + random.nextInt(6); // 12-17 reps
    } else {
      sets = 3; // Default
      reps = 10 + random.nextInt(5); // 10-14 reps
    }

    // Calculate training minutes based on workout type
    int trainingMinutes;
    if (baseWorkout['exercise_types'] == 'Cardio' || baseWorkout['exercise_types'] == 'HIIT') {
      trainingMinutes = 20 + random.nextInt(20); // 20-40 minutes
    } else if (baseWorkout['exercise_types'] == 'Strength Training') {
      trainingMinutes = 30 + random.nextInt(20); // 30-50 minutes
    } else {
      trainingMinutes = 25 + random.nextInt(15); // 25-40 minutes
    }

    return {
      'name': baseWorkout['name'],
      'sets': sets,
      'reps': reps,
      'weight': (baseWeight + random.nextInt(20) - 10).round(), // Add some variation
      'training_minutes': trainingMinutes,
      'exercise_types': baseWorkout['exercise_types'],
    };
  }
}
