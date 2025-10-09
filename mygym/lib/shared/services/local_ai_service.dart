import 'dart:convert';
import 'dart:math';

class LocalAIService {
  static final Random _random = Random();

  // Generate meal plan using local AI-like logic
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
    
    print('🤖 LOCAL AI: Generating meal plan for user $userId');
    print('🤖 LOCAL AI: Target: ${targetDailyCalories.toStringAsFixed(0)} cal, ${dailyProteins.toStringAsFixed(1)}g protein, ${dailyCarbs.toStringAsFixed(1)}g carbs, ${dailyFats.toStringAsFixed(1)}g fats');
    print('🤖 LOCAL AI: Training data: ${trainingData?['has_training'] == true ? 'Active training' : 'No training'}');
    
    final List<Map<String, dynamic>> items = [];
    final startDateObj = DateTime.parse(startDate);
    
    // Gym-friendly meal database
    final mealDatabase = _getMealDatabase(mealPlan, trainingData);
    
    for (int day = 0; day < totalDays; day++) {
      final currentDate = startDateObj.add(Duration(days: day));
      final dateStr = currentDate.toIso8601String().split('T').first;
      
      // Generate meals for each day
      final meals = ['Breakfast', 'Lunch', 'Dinner'];
      final mealRatios = [0.25, 0.40, 0.35]; // Breakfast, Lunch, Dinner calorie distribution
      
      for (int mealIndex = 0; mealIndex < meals.length; mealIndex++) {
        final mealType = meals[mealIndex];
        final ratio = mealRatios[mealIndex];
        
        // Select random meal from database
        final mealOptions = mealDatabase[mealType.toLowerCase()] ?? [];
        final selectedMeal = mealOptions[_random.nextInt(mealOptions.length)];
        
        // Calculate nutritional values based on target ratios
        final mealCalories = (targetDailyCalories * ratio).round();
        final mealProteins = (dailyProteins * ratio).round();
        final mealCarbs = (dailyCarbs * ratio).round();
        final mealFats = (dailyFats * ratio).round();
        
        // Adjust for training days
        final adjustedValues = _adjustForTraining(selectedMeal, mealCalories, mealProteins, mealCarbs, mealFats, trainingData, mealType);
        
        items.add({
          'meal_type': mealType,
          'food_item_name': adjustedValues['name'],
          'grams': adjustedValues['grams'],
          'calories': adjustedValues['calories'],
          'proteins': adjustedValues['proteins'],
          'fats': adjustedValues['fats'],
          'carbs': adjustedValues['carbs'],
          'date': dateStr,
        });
      }
    }
    
    final result = {
      'user_id': userId,
      'start_date': startDate,
      'end_date': endDate,
      'meal_plan': mealPlan,
      'total_days': totalDays,
      'items': items,
    };
    
    print('🤖 LOCAL AI: Generated ${items.length} meal items for $totalDays days');
    return result;
  }
  
  // Get meal database based on plan type and training data
  Map<String, List<Map<String, dynamic>>> _getMealDatabase(String mealPlan, Map<String, dynamic>? trainingData) {
    final isMuscleGain = mealPlan.toLowerCase().contains('muscle') || mealPlan.toLowerCase().contains('gain');
    final hasTraining = trainingData?['has_training'] == true;
    
    return {
      'breakfast': [
        {
          'name': 'Protein Oatmeal with Berries and Almonds',
          'base_calories': 400,
          'base_protein': 25,
          'base_carbs': 50,
          'base_fats': 12,
          'base_grams': 300,
        },
        {
          'name': 'Greek Yogurt Parfait with Granola',
          'base_calories': 350,
          'base_protein': 30,
          'base_carbs': 35,
          'base_fats': 8,
          'base_grams': 280,
        },
        {
          'name': 'Scrambled Eggs with Whole Wheat Toast',
          'base_calories': 380,
          'base_protein': 28,
          'base_carbs': 30,
          'base_fats': 15,
          'base_grams': 250,
        },
        {
          'name': 'Protein Smoothie Bowl with Banana',
          'base_calories': 420,
          'base_protein': 32,
          'base_carbs': 45,
          'base_fats': 10,
          'base_grams': 350,
        },
        {
          'name': 'Avocado Toast with Poached Eggs',
          'base_calories': 360,
          'base_protein': 22,
          'base_carbs': 25,
          'base_fats': 18,
          'base_grams': 220,
        },
      ],
      'lunch': [
        {
          'name': 'Grilled Chicken Breast with Quinoa Salad',
          'base_calories': 500,
          'base_protein': 45,
          'base_carbs': 40,
          'base_fats': 12,
          'base_grams': 350,
        },
        {
          'name': 'Salmon with Sweet Potato and Broccoli',
          'base_calories': 480,
          'base_protein': 40,
          'base_carbs': 35,
          'base_fats': 18,
          'base_grams': 320,
        },
        {
          'name': 'Turkey Wrap with Mixed Vegetables',
          'base_calories': 450,
          'base_protein': 35,
          'base_carbs': 30,
          'base_fats': 15,
          'base_grams': 280,
        },
        {
          'name': 'Lean Beef with Brown Rice and Green Beans',
          'base_calories': 520,
          'base_protein': 42,
          'base_carbs': 45,
          'base_fats': 14,
          'base_grams': 380,
        },
        {
          'name': 'Tuna Salad with Mixed Greens',
          'base_calories': 420,
          'base_protein': 38,
          'base_carbs': 20,
          'base_fats': 16,
          'base_grams': 300,
        },
      ],
      'dinner': [
        {
          'name': 'Baked Chicken Breast with Roasted Vegetables',
          'base_calories': 450,
          'base_protein': 50,
          'base_carbs': 20,
          'base_fats': 12,
          'base_grams': 400,
        },
        {
          'name': 'Grilled Fish with Quinoa and Asparagus',
          'base_calories': 480,
          'base_protein': 45,
          'base_carbs': 35,
          'base_fats': 16,
          'base_grams': 350,
        },
        {
          'name': 'Lean Steak with Roasted Potatoes',
          'base_calories': 500,
          'base_protein': 40,
          'base_carbs': 30,
          'base_fats': 20,
          'base_grams': 380,
        },
        {
          'name': 'Turkey Meatballs with Whole Wheat Pasta',
          'base_calories': 460,
          'base_protein': 35,
          'base_carbs': 40,
          'base_fats': 14,
          'base_grams': 320,
        },
        {
          'name': 'Baked Cod with Rice and Steamed Vegetables',
          'base_calories': 440,
          'base_protein': 42,
          'base_carbs': 35,
          'base_fats': 12,
          'base_grams': 340,
        },
      ],
    };
  }
  
  // Adjust meal values based on training data
  Map<String, dynamic> _adjustForTraining(
    Map<String, dynamic> meal,
    int targetCalories,
    int targetProteins,
    int targetCarbs,
    int targetFats,
    Map<String, dynamic>? trainingData,
    String mealType,
  ) {
    final hasTraining = trainingData?['has_training'] == true;
    final intensity = trainingData?['training_intensity'] as String? ?? 'low';
    
    if (!hasTraining) {
      return {
        'name': meal['name'],
        'grams': meal['base_grams'],
        'calories': targetCalories,
        'proteins': targetProteins,
        'carbs': targetCarbs,
        'fats': targetFats,
      };
    }
    
    // Adjust based on training intensity and meal timing
    double calorieMultiplier = 1.0;
    double proteinMultiplier = 1.0;
    double carbMultiplier = 1.0;
    double fatMultiplier = 1.0;
    
    if (intensity == 'high') {
      calorieMultiplier = 1.15;
      proteinMultiplier = 1.20;
      carbMultiplier = 1.10;
    } else if (intensity == 'moderate') {
      calorieMultiplier = 1.08;
      proteinMultiplier = 1.12;
      carbMultiplier = 1.05;
    }
    
    // Meal timing adjustments
    if (mealType == 'Breakfast') {
      // Pre-workout meal - more carbs for energy
      carbMultiplier *= 1.1;
    } else if (mealType == 'Lunch') {
      // Post-workout meal - more protein for recovery
      proteinMultiplier *= 1.15;
    } else if (mealType == 'Dinner') {
      // Recovery meal - balanced with slight protein boost
      proteinMultiplier *= 1.05;
    }
    
    return {
      'name': meal['name'],
      'grams': (meal['base_grams'] * calorieMultiplier).round(),
      'calories': (targetCalories * calorieMultiplier).round(),
      'proteins': (targetProteins * proteinMultiplier).round(),
      'carbs': (targetCarbs * carbMultiplier).round(),
      'fats': (targetFats * fatMultiplier).round(),
    };
  }
}
