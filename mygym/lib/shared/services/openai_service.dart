import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class OpenAIService {
  final Dio _dio;

  OpenAIService._internal(this._dio);

  factory OpenAIService() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.openAIBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppConfig.openAIApiKey}',
      },
    ));
    return OpenAIService._internal(dio);
  }

  Future<Map<String, dynamic>> generatePlanJson({
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
    if (AppConfig.openAIApiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    final system = 'You are an expert fitness trainer and workout plan creator. Create personalized, realistic workout plans based on user goals, fitness level, and physical characteristics. Produce ONLY valid JSON.';
    
    // Calculate realistic plan duration based on goal
    int planDays = 7;
    if (futureGoal.toLowerCase().contains('weight loss') || futureGoal.toLowerCase().contains('lose weight')) {
      planDays = 30; // 4 weeks for weight loss
    } else if (futureGoal.toLowerCase().contains('muscle') || futureGoal.toLowerCase().contains('strength')) {
      planDays = 28; // 4 weeks for muscle building
    } else if (futureGoal.toLowerCase().contains('endurance') || futureGoal.toLowerCase().contains('cardio')) {
      planDays = 21; // 3 weeks for endurance
    }
    
    // Calculate realistic workout schedule
    int workoutsPerWeek = 4;
    if (futureGoal.toLowerCase().contains('beginner')) {
      workoutsPerWeek = 3;
    } else if (futureGoal.toLowerCase().contains('advanced')) {
      workoutsPerWeek = 5;
    }
    
    final totalWorkouts = (planDays / 7 * workoutsPerWeek).round();
    final totalMinutes = totalWorkouts * 45; // 45 minutes per workout
    
    final user = {
      'user_id': userId,
      'start_date': startDate,
      'end_date': endDate,
      'exercise_plan': exercisePlan,
      'total_workouts': totalWorkouts,
      'total_training_minutes': totalMinutes,
      'age': age,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'gender': gender,
      'future_goal': futureGoal,
      'plan_duration_days': planDays,
    };

    final res = await _dio.post('/chat/completions', data: {
      'model': AppConfig.openAIModel,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': 'Create a personalized workout plan for a ${age}-year-old ${gender.toLowerCase()} who weighs ${weightKg}kg and is ${heightCm}cm tall. Their goal is: "${futureGoal}" and they want a ${exercisePlan} plan.\n\n'
              'Generate a realistic workout plan with ${totalWorkouts} workouts over ${planDays} days, totaling ${totalMinutes} minutes.\n\n'
              'Create specific, varied workout names (not generic "Test Workout"). Include different exercise types like:\n'
              '- Strength training (Upper Body, Lower Body, Core)\n'
              '- Cardio (HIIT, Steady State, Interval)\n'
              '- Functional training (Full Body, Circuit)\n'
              '- Recovery (Stretching, Mobility)\n\n'
              'Make workout names descriptive and professional (e.g., "Upper Body Strength Training", "HIIT Cardio Blast", "Core Stability Work").\n\n'
              'JSON schema: {"user_id": number, "start_date": string, "end_date": string, "exercise_plan": string, '
              '"total_workouts": number, "total_training_minutes": number, '
              '"items": [{"name": string, "sets": number, "reps": number, "weight": number, "training_minutes": number, "exercise_types": string}]}\n\n'
              'User data: ${jsonEncode(user)}'
        }
      ],
      'temperature': 0.3,
      'response_format': {'type': 'json_object'},
    });

    if (res.statusCode == 200) {
      final msg = res.data['choices'][0]['message']['content'];
      final parsed = jsonDecode(msg);
      return Map<String, dynamic>.from(parsed);
    }
    throw Exception('OpenAI generation failed: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> generateMealPlanJson({
    required int userId,
    required String mealPlan,
    required String startDate,
    required String endDate,
    required int age,
    required int heightCm,
    required int weightKg,
    required String gender,
    required String futureGoal,
    required String country,
    required int totalDays,
    required double targetDailyCalories,
    required double dailyProteins,
    required double dailyCarbs,
    required double dailyFats,
    Map<String, dynamic>? trainingData,
  }) async {
    if (AppConfig.openAIApiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    final system = 'You are a professional nutritionist and fitness expert. Create personalized meal plans optimized for gym workouts and fitness goals. Focus on high-protein, balanced nutrition suitable for active individuals. Produce ONLY valid JSON.';
    
    final user = {
      'user_id': userId,
      'start_date': startDate,
      'end_date': endDate,
      'meal_plan': mealPlan,
      'total_days': totalDays,
      'age': age,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'gender': gender,
      'future_goal': futureGoal,
      'country': country,
      'target_daily_calories': targetDailyCalories,
      'daily_proteins': dailyProteins,
      'daily_carbs': dailyCarbs,
      'daily_fats': dailyFats,
      'training_data': trainingData ?? {},
    };

    final res = await _dio.post('/chat/completions', data: {
      'model': AppConfig.openAIModel,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': 'Generate a personalized gym-optimized meal plan JSON with the following requirements:\n'
              '1. Create ${totalDays} days of meals\n'
              '2. Each day should have Breakfast, Lunch, and Dinner\n'
              '3. Use gym-friendly, high-protein meals like grilled chicken, salmon, lean beef, eggs, Greek yogurt, quinoa, brown rice, sweet potatoes, vegetables, nuts, etc.\n'
              '4. Ensure meals are healthy and nutritious (no processed foods, limit sugar)\n'
              '5. Target daily nutrition: ${targetDailyCalories.toStringAsFixed(0)} calories, ${dailyProteins.toStringAsFixed(1)}g protein, ${dailyCarbs.toStringAsFixed(1)}g carbs, ${dailyFats.toStringAsFixed(1)}g fats\n'
              '6. Make each day unique with different dishes and cooking methods\n'
              '7. Focus on gym-friendly, high-protein options for muscle building and recovery\n'
              '8. Use easy-to-cook, meal-prep friendly recipes\n'
              '${trainingData != null && trainingData['has_training'] == true ? '\n9. TRAINING INTEGRATION: User has active training with ${trainingData['training_intensity']} intensity, ${trainingData['avg_training_minutes']} minutes per day, ${trainingData['workout_frequency']} frequency. Adjust meal timing and protein distribution accordingly:\n'
                  '- Pre-workout: Light carbs for energy (1-2 hours before)\n'
                  '- Post-workout: High protein for recovery (within 30-60 minutes)\n'
                  '- Training days: Higher protein and carb intake\n'
                  '- Rest days: Moderate protein, focus on recovery foods\n'
                  '- Exercise types: ${trainingData['exercise_types']?.join(', ') ?? 'general'}\n' : '\n9. No active training detected - focus on general fitness nutrition with balanced macros.'}\n\n'
              'JSON Schema: {"user_id": number, "start_date": string, "end_date": string, "meal_plan": string, "total_days": number, '
              '"items": [{"meal_type": "Breakfast|Lunch|Dinner", "food_item_name": string, "grams": number, "calories": number, "proteins": number, "fats": number, "carbs": number, "date": "YYYY-MM-DD"}]}\n\n'
              'User details: ${jsonEncode(user)}'
        }
      ],
      'temperature': 0.3,
      'response_format': {'type': 'json_object'},
    });

    if (res.statusCode == 200) {
      final msg = res.data['choices'][0]['message']['content'];
      final parsed = jsonDecode(msg);
      return Map<String, dynamic>.from(parsed);
    }
    throw Exception('OpenAI meal plan generation failed: ${res.statusCode}');
  }
}


