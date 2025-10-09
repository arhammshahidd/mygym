import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import '../../domain/models/meal_plan.dart';
import '../../data/services/ai_nutrition_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/services/food_menu_service.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../trainings/presentation/controllers/plans_controller.dart';

class NutritionController extends GetxController {
  final RxList<MealPlan> schedules = <MealPlan>[].obs;
  final Rx<MealPlan?> assignedPlan = Rx<MealPlan?>(null);
  final RxInt activeDayIndex = 0.obs;
  final RxBool mealPlanActive = false.obs;
  // Tracks which plan is actively started: 'assigned' (Schedules) or 'ai'
  final RxString _activeMealSource = 'none'.obs;

  // AI state
  final Rx<MealPlan?> aiGeneratedPlan = Rx<MealPlan?>(null);
  final RxList<Map<String, dynamic>> generatedPlans = <Map<String, dynamic>>[].obs;
  final Rx<AIPlanStatus> aiStatus = AIPlanStatus.draft.obs;
  final RxBool aiLoading = false.obs;
  final Rx<Map<String, dynamic>?> lastAiPayload = Rx<Map<String, dynamic>?>(null);
  final AiNutritionService _ai = AiNutritionService();
  final FoodMenuService _food = FoodMenuService();
  final PlansController _plansController = Get.find<PlansController>();

  @override
  void onInit() {
    super.onInit();
    loadAssignedFromBackend();
    // Clear any cached dummy data and load real plans from backend
    aiGeneratedPlan.value = null;
    aiStatus.value = AIPlanStatus.draft;
    loadGeneratedPlansFromBackend();

    // Load persisted meal plan state and advance day if past midnight
    _restoreMealPlanState().then((_) => _maybeAdvanceMealDayForToday());
  }

  // Removed _seedDemoData() - now using real AI-generated plans from backend

  double _calculateBMR(int weight, int height, int age, String gender) {
    // Mifflin-St Jeor Equation for BMR calculation
    if (gender.toLowerCase() == 'female') {
      return (10 * weight) + (6.25 * height) - (5 * age) - 161;
    } else {
      return (10 * weight) + (6.25 * height) - (5 * age) + 5;
    }
  }

  int _calculateOptimalPlanDuration(int currentWeight, String goal) {
    // Extract target weight from goal text (e.g., "lose weight till 58" -> 58kg)
    final targetWeightMatch = RegExp(r'(\d+)').firstMatch(goal);
    if (targetWeightMatch != null) {
      final targetWeight = int.tryParse(targetWeightMatch.group(1) ?? '') ?? currentWeight;
      final weightLoss = currentWeight - targetWeight;
      
      // AI decides duration based on weight loss amount
      if (weightLoss <= 2) {
        return 30; // 1 month for 2kg or less
      } else if (weightLoss <= 5) {
        return 60; // 2 months for 3-5kg
      } else if (weightLoss <= 8) {
        return 90; // 3 months for 6-8kg
      } else if (weightLoss <= 12) {
        return 120; // 4 months for 9-12kg
      } else {
        return 150; // 5 months for 12kg+
      }
    }
    
    // Default to 30 days if no target weight found
    return 30;
  }

  // Get user's training data to enhance nutrition plan
  Map<String, dynamic> _getUserTrainingData() {
    try {
      // Get user's active training plans
      final assignments = _plansController.manualPlans; // Using manual plans as assignments for now
      final aiGenerated = _plansController.aiGeneratedPlans;
      
      if (assignments.isEmpty && aiGenerated.isEmpty) {
        return {
          'has_training': false,
          'total_training_days': 0,
          'avg_training_minutes': 0,
          'workout_frequency': 'none',
          'exercise_types': [],
          'training_intensity': 'low',
        };
      }

      // Analyze training data
      int totalTrainingDays = 0;
      int totalTrainingMinutes = 0;
      List<String> exerciseTypes = [];
      String workoutFrequency = 'low';
      String trainingIntensity = 'low';

      // Process assignments (active training plans)
      for (final assignment in assignments) {
        final plan = assignment;
        final days = int.tryParse((plan['total_days'] ?? plan['days'] ?? 0).toString()) ?? 0;
        final minutes = int.tryParse((plan['total_training_minutes'] ?? plan['training_minutes'] ?? 0).toString()) ?? 0;
        final items = plan['items'] as List? ?? [];
        
        totalTrainingDays += days;
        totalTrainingMinutes += minutes;
        
        // Extract exercise types
        for (final item in items) {
          if (item is Map) {
            final type = item['exercise_types']?.toString();
            if (type != null && !exerciseTypes.contains(type)) {
              exerciseTypes.add(type);
            }
          }
        }
      }

      // Process AI generated plans
      for (final plan in aiGenerated) {
        final days = int.tryParse((plan['total_days'] ?? plan['days'] ?? 0).toString()) ?? 0;
        final minutes = int.tryParse((plan['total_training_minutes'] ?? plan['training_minutes'] ?? 0).toString()) ?? 0;
        final items = plan['items'] as List? ?? [];
        
        totalTrainingDays += days;
        totalTrainingMinutes += minutes;
        
        // Extract exercise types
        for (final item in items) {
          if (item is Map) {
            final type = item['exercise_types']?.toString();
            if (type != null && !exerciseTypes.contains(type)) {
              exerciseTypes.add(type);
            }
          }
        }
      }

      // Calculate averages and intensity
      final avgTrainingMinutes = totalTrainingDays > 0 ? (totalTrainingMinutes / totalTrainingDays).round() : 0;
      
      if (avgTrainingMinutes >= 90) {
        trainingIntensity = 'high';
        workoutFrequency = 'daily';
      } else if (avgTrainingMinutes >= 60) {
        trainingIntensity = 'moderate';
        workoutFrequency = '5-6_days_per_week';
      } else if (avgTrainingMinutes >= 30) {
        trainingIntensity = 'moderate';
        workoutFrequency = '3-4_days_per_week';
      } else {
        trainingIntensity = 'low';
        workoutFrequency = '2-3_days_per_week';
      }

      return {
        'has_training': true,
        'total_training_days': totalTrainingDays,
        'avg_training_minutes': avgTrainingMinutes,
        'total_training_minutes': totalTrainingMinutes,
        'workout_frequency': workoutFrequency,
        'exercise_types': exerciseTypes,
        'training_intensity': trainingIntensity,
        'active_plans_count': assignments.length + aiGenerated.length,
      };
    } catch (e) {
      print('Error getting training data: $e');
      return {
        'has_training': false,
        'total_training_days': 0,
        'avg_training_minutes': 0,
        'workout_frequency': 'none',
        'exercise_types': [],
        'training_intensity': 'low',
      };
    }
  }

  Future<void> loadAssignedFromBackend() async {
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final userId = profile.user?.id;
      final list = await _food.listAssignments(userId: userId);
      if (list.isEmpty) return;
      final latest = list.first; // assume latest or server sorted

      List<Map<String, dynamic>> parseMeal(dynamic raw) {
        if (raw == null) return [];
        try {
          final dynamic decoded = (raw is String) ? jsonDecode(raw) : raw;
          final List<Map<String, dynamic>> normalized = [];

          void addWithDay(Map<String, dynamic> item, int indexFallback) {
            final hasDay = item.containsKey('day') || item.containsKey('dayNumber') || item.containsKey('day_number');
            if (!hasDay) {
              item['day'] = indexFallback + 1; // infer sequential day if missing
            } else if (!item.containsKey('day') && item.containsKey('dayNumber')) {
              item['day'] = item['dayNumber'];
            } else if (!item.containsKey('day') && item.containsKey('day_number')) {
              item['day'] = item['day_number'];
            }
            normalized.add(Map<String, dynamic>.from(item));
          }

          if (decoded is List) {
            for (int i = 0; i < decoded.length; i++) {
              final e = decoded[i];
              if (e is Map) {
                addWithDay(Map<String, dynamic>.from(e), i);
              } else if (e is List) {
                for (final inner in e) {
                  if (inner is Map) addWithDay(Map<String, dynamic>.from(inner), i);
                }
              }
            }
            return normalized;
          }
          if (decoded is Map) {
            final listLike = decoded['items'] ?? decoded['list'] ?? decoded['data'];
            if (listLike is List) {
              for (int i = 0; i < listLike.length; i++) {
                final e = listLike[i];
                if (e is Map) addWithDay(Map<String, dynamic>.from(e), i);
              }
              return normalized;
            }
          }
          return [];
        } catch (_) {
          return [];
        }
      }

      final breakfast = parseMeal(latest['breakfast']);
      final lunch = parseMeal(latest['lunch']);
      final dinner = parseMeal(latest['dinner']);

      MealItem toItem(Map<String, dynamic> m) => MealItem(
            name: (m['food_item_name'] ?? m['name'] ?? m['item'] ?? 'Food').toString(),
            calories: (m['calories'] is num)
                ? (m['calories'] as num).round()
                : int.tryParse('${m['calories'] ?? m['kcal']}') ?? 0,
            proteinGrams: (m['protein'] is num)
                ? (m['protein'] as num).round()
                : int.tryParse('${m['protein'] ?? m['protein_g'] ?? m['proteins']}') ?? 0,
            carbsGrams: (m['carbs'] is num)
                ? (m['carbs'] as num).round()
                : int.tryParse('${m['carbs'] ?? m['carbohydrates'] ?? m['carbs_g']}') ?? 0,
            fatGrams: (m['fats'] is num)
                ? (m['fats'] as num).round()
                : int.tryParse('${m['fats'] ?? m['fat'] ?? m['fat_g']}') ?? 0,
            grams: (m['grams'] is num) ? (m['grams'] as num).round() : int.tryParse('${m['grams']}') ?? 0,
          );

      // Group by day
      final Map<int, DayMeals> dayMap = {};
      void addItems(List<Map<String, dynamic>> list, MealType type) {
        for (final m in list) {
          final int day = (m['day'] is num) ? (m['day'] as num).toInt() : int.tryParse('${m['day']}') ?? 1;
          final existing = dayMap[day];
          final item = toItem(m);
          if (existing == null) {
            dayMap[day] = DayMeals(
              dayNumber: day,
              breakfast: type == MealType.breakfast ? [item] : <MealItem>[],
              lunch: type == MealType.lunch ? [item] : <MealItem>[],
              dinner: type == MealType.dinner ? [item] : <MealItem>[],
            );
          } else {
            if (type == MealType.breakfast) {
              existing.breakfast.add(item);
            } else if (type == MealType.lunch) {
              existing.lunch.add(item);
            } else {
              existing.dinner.add(item);
            }
          }
        }
      }

      addItems(breakfast, MealType.breakfast);
      addItems(lunch, MealType.lunch);
      addItems(dinner, MealType.dinner);

      // Compute total days from assignment dates; fill missing days
      int totalDays = 0;
      try {
        final String? sd = latest['start_date']?.toString();
        final String? ed = latest['end_date']?.toString();
        if (sd != null && ed != null && sd.isNotEmpty && ed.isNotEmpty) {
          final start = DateTime.parse(sd);
          final end = DateTime.parse(ed);
          // Use exclusive end difference to avoid off-by-one; minimum 1 day span
          totalDays = end.difference(start).inDays;
          if (totalDays <= 0) totalDays = 1;
        }
      } catch (_) {
        totalDays = 0;
      }

      // Ensure day entries exist for the whole span
      if (totalDays > 0) {
        final existingDaysSorted = dayMap.keys.toList()..sort();
        // If no template days exist, keep empty placeholders
        for (int d = 1; d <= totalDays; d++) {
          if (!dayMap.containsKey(d)) {
            if (existingDaysSorted.isNotEmpty) {
              // Repeat templates in order and shuffle items deterministically per day
              final int templateIndex = (d - 1) % existingDaysSorted.length;
              final DayMeals template = dayMap[existingDaysSorted[templateIndex]]!;
              List<MealItem> shuffledCopy(List<MealItem> src, int seed) {
                final list = List<MealItem>.from(src);
                list.shuffle(Random(seed));
                return list;
              }
              dayMap[d] = DayMeals(
                dayNumber: d,
                breakfast: shuffledCopy(template.breakfast, d * 31 + 1),
                lunch: shuffledCopy(template.lunch, d * 31 + 2),
                dinner: shuffledCopy(template.dinner, d * 31 + 3),
              );
            } else {
              dayMap[d] = DayMeals(dayNumber: d, breakfast: <MealItem>[], lunch: <MealItem>[], dinner: <MealItem>[]);
            }
          }
        }
      }

      final days = dayMap.keys.toList()..sort();
      final builtDays = days.map((d) => dayMap[d]!).toList();

      final title = (latest['menu_plan_category']?.toString().trim().isNotEmpty == true)
          ? latest['menu_plan_category'].toString()
          : 'Assigned Nutrition Plan';

      final plan = MealPlan(
        id: 'assign_${latest['id']}',
        title: title,
        category: title.toLowerCase().contains('weight') ? PlanCategory.weightLoss : PlanCategory.muscleGain,
        note: latest['notes']?.toString() ?? '',
        days: builtDays,
      );

      assignedPlan.value = plan;
      activeDayIndex.value = 0;
    } catch (e) {
      // silent fail; page can still show local plans
    }
  }
  void assignPlan(MealPlan plan) {
    assignedPlan.value = plan;
    activeDayIndex.value = 0;
  }

  void startPlan() {
    // Start the assigned (Schedules) plan
    if (assignedPlan.value != null) {
      activeDayIndex.value = 0;
      mealPlanActive.value = true;
      _activeMealSource.value = 'assigned';
      _persistMealPlanState();
    }
  }

  /// Expose a JSON snapshot of today's meals for dashboard (Schedules source)
  Map<String, dynamic>? get todayMealsSnapshot {
    try {
      if (!mealPlanActive.value) return null;
      final src = _activeMealSource.value;
      final plan = src == 'assigned' ? assignedPlan.value : aiGeneratedPlan.value;
      if (plan == null || plan.days.isEmpty) return null;
      final idx = activeDayIndex.value.clamp(0, plan.days.length - 1);
      final day = plan.days[idx];
      return {
        'title': plan.title,
        'day': idx + 1,
        'breakfast': day.breakfast.map((m) => {
          'name': m.name, 
          'cal': m.calories,
          'calories': m.calories,
          'protein': m.proteinGrams,
          'carbs': m.carbsGrams,
          'fats': m.fatGrams,
        }).toList(),
        'lunch': day.lunch.map((m) => {
          'name': m.name, 
          'cal': m.calories,
          'calories': m.calories,
          'protein': m.proteinGrams,
          'carbs': m.carbsGrams,
          'fats': m.fatGrams,
        }).toList(),
        'dinner': day.dinner.map((m) => {
          'name': m.name, 
          'cal': m.calories,
          'calories': m.calories,
          'protein': m.proteinGrams,
          'carbs': m.carbsGrams,
          'fats': m.fatGrams,
        }).toList(),
      };
    } catch (_) {
      return null;
    }
  }

  void stopPlan() {
    mealPlanActive.value = false;
    _activeMealSource.value = 'none';
    _persistMealPlanState();
  }

  Future<void> deleteAiPlan() async {
    try {
      // Clear local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ai_meal_plan_cache');
      
      // Clear UI state
      aiGeneratedPlan.value = null;
      aiStatus.value = AIPlanStatus.draft;
      lastAiPayload.value = null;
      
      // TODO: If plan has database ID, call delete API endpoint
      // final planId = aiGeneratedPlan.value?.id;
      // if (planId != null && planId != 'ai_generated') {
      //   await _ai.deletePlan(planId);
      // }
    } catch (e) {
      // Silent fail - UI is already cleared
    }
  }

  void setActiveDay(int index) {
    activeDayIndex.value = index;
    _persistMealPlanState();
  }

  // Start AI generated plan as the active meal plan
  void startAiPlan() {
    if (aiGeneratedPlan.value != null) {
      activeDayIndex.value = 0;
      mealPlanActive.value = true;
      _activeMealSource.value = 'ai';
      _persistMealPlanState();
    }
  }

  Future<void> _persistMealPlanState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Get.find<ProfileController>().user?.id ?? 0;
      await prefs.setBool('nutrition_meal_active_user_$userId', mealPlanActive.value);
      await prefs.setString('nutrition_active_source_user_$userId', _activeMealSource.value);
      await prefs.setInt('nutrition_active_day_index_user_$userId', activeDayIndex.value);
      // Store last rollover date as yyyy-MM-dd
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await prefs.setString('nutrition_last_rollover', today);
      // Optionally store plan identity for AI vs assigned
      if (_activeMealSource.value == 'ai') {
        await prefs.setString('nutrition_active_plan_id_user_$userId', aiGeneratedPlan.value?.id ?? 'ai_generated');
      } else if (_activeMealSource.value == 'assigned') {
        await prefs.setString('nutrition_active_plan_id_user_$userId', assignedPlan.value?.id ?? 'assigned_plan');
      } else {
        await prefs.remove('nutrition_active_plan_id_user_$userId');
      }
    } catch (_) {}
  }

  Future<void> _restoreMealPlanState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Get.find<ProfileController>().user?.id ?? 0;
      mealPlanActive.value = prefs.getBool('nutrition_meal_active_user_$userId') ?? false;
      _activeMealSource.value = prefs.getString('nutrition_active_source_user_$userId') ?? 'none';
      activeDayIndex.value = prefs.getInt('nutrition_active_day_index_user_$userId') ?? 0;
    } catch (_) {}
  }

  Future<void> _maybeAdvanceMealDayForToday() async {
    try {
      if (!mealPlanActive.value) return;

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('nutrition_last_rollover');
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      if (last == null || last.isEmpty) {
        await prefs.setString('nutrition_last_rollover', todayStr);
        return;
      }

      if (last != todayStr) {
        // Compute how many days passed and advance accordingly
        DateTime? lastDate;
        try { lastDate = DateTime.parse(last); } catch (_) {}
        final now = DateTime.now();
        int deltaDays = 1;
        if (lastDate != null) {
          deltaDays = now.difference(DateTime(lastDate.year, lastDate.month, lastDate.day)).inDays;
          if (deltaDays < 1) deltaDays = 1;
        }

        // Determine plan length from active source
        int totalDays = 0;
        if (_activeMealSource.value == 'ai' && aiGeneratedPlan.value != null) {
          totalDays = aiGeneratedPlan.value!.days.length;
        } else if (_activeMealSource.value == 'assigned' && assignedPlan.value != null) {
          totalDays = assignedPlan.value!.days.length;
        }

        if (totalDays > 0) {
          activeDayIndex.value = (activeDayIndex.value + deltaDays).clamp(0, totalDays - 1);
        }
        await prefs.setString('nutrition_last_rollover', todayStr);
        await prefs.setInt('nutrition_active_day_index', activeDayIndex.value);
      }
    } catch (_) {}
  }

  // AI generation - now uses real AI backend
  Future<void> generateAiPlan({required PlanCategory category}) async {
    // This method is now replaced by createGeneratedPlan which uses real AI
    // Keeping for backward compatibility but redirecting to the form
    throw Exception('Please use the AI form to generate plans with real AI data');
  }

  Future<void> createGeneratedPlan({required Map<String, dynamic> form}) async {
    aiLoading.value = true;
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      
      // Compute default date range (30 days) if not provided
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final DateTime start = () {
        final s = form['start_date']?.toString();
        if (s != null && s.isNotEmpty) {
          try { return DateTime.parse(s); } catch (_) {}
        }
        return DateTime.now();
      }();
      final DateTime end = () {
        final e = form['end_date']?.toString();
        if (e != null && e.isNotEmpty) {
          try { return DateTime.parse(e); } catch (_) {}
        }
        return start.add(const Duration(days: 30));
      }();
      
      String apiCategoryLabel() {
        final raw = (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss');
        final v = raw.toString().toLowerCase();
        // Match backend labels exactly
        if (v.contains('muscle')) return 'Muscle Gain';
        if (v.contains('lose') || v.contains('loss')) return 'Weight Lose';
        return 'Weight Lose';
      }
      // Debug: Print essential form data (reduced for web compatibility)
      print('Form data: age=${form['age']}, height=${form['height']}, weight=${form['weight']}, gender=${form['gender']}');
      
      // Parse form values with better error handling
      final String ageStr = form['age']?.toString().trim() ?? '';
      final String heightStr = form['height']?.toString().trim() ?? '';
      final String weightStr = form['weight']?.toString().trim() ?? '';
      final String gender = form['gender']?.toString() ?? '';
      final String country = form['country']?.toString() ?? '';
      final String illness = form['illness']?.toString() ?? '';
      final String goal = form['goal']?.toString() ?? '';
      
      // Parse numeric values
      final int age = int.tryParse(ageStr) ?? 0;
      final int height = int.tryParse(heightStr) ?? 0;
      final int weight = int.tryParse(weightStr) ?? 0;
      
      // Enhanced validation with better error messages
      if (ageStr.isEmpty || age == 0) {
        throw Exception('Age is required and must be a valid number. Got: "$ageStr"');
      }
      if (heightStr.isEmpty || height == 0) {
        throw Exception('Height is required and must be a valid number. Got: "$heightStr"');
      }
      if (weightStr.isEmpty || weight == 0) {
        throw Exception('Weight is required and must be a valid number. Got: "$weightStr"');
      }
      if (gender.isEmpty) {
        throw Exception('Gender is required. Got: "$gender"');
      }

      // Create AI request to obtain request_id (DB requires NOT NULL)
      // Step 1: Submit User Form Data to /api/appAIMeals/requests
      // Ensure we're sending the exact values from the form
      // Debug: Print essential values being sent
      print('AI request: ${height}cm, ${weight}kg, ${age}yo, $gender, $country');
      
      // Use default user ID if profile is not loaded
      final userId = user?.id ?? 1;
      if (user?.id == null) {
        print('User ID not available - using default user ID: $userId');
      }
      
      final requestPayload = {
        'user_id': userId,
        'meal_plan': apiCategoryLabel(), // e.g., "Weight Loss Plan"
        'age': age,
        'height_cm': height, // This should be 155.0 from your form
        'weight_kg': weight, // This should be 65.0 from your form
        'gender': gender.toLowerCase(), // "male", "female", "other"
        'country': country.isEmpty ? 'Pakistan' : country, // Default to Pakistan if empty
        'illness': illness.isEmpty ? null : illness,
        'future_goal': goal,
        // Gym/Fitness specific requirements
        'activity_level': 'high', // Gym workouts
        'workout_frequency': '5-6_days_per_week',
        'workout_type': 'strength_training',
        'fitness_goal': apiCategoryLabel().toLowerCase().contains('weight') ? 'fat_loss' : 'muscle_gain',
        'training_schedule': 'gym_based',
        'pre_workout_nutrition': true,
        'post_workout_nutrition': true,
        'recovery_focus': true,
        // Dietary restrictions - exclude pork
        'dietary_restrictions': ['no_pork', 'no_pork_products'],
        'excluded_foods': ['pork', 'bacon', 'ham', 'sausage', 'pork_chops', 'pork_tenderloin', 'pork_shoulder', 'pork_belly'],
        'religious_dietary': 'halal', // Indicates no pork allowed
        // Gym-specific preferences
        'gym_friendly': true,
        'meal_timing': 'workout_optimized',
        'protein_timing': 'peri_workout',
        // Pakistani cuisine preferences
        'cuisine_preference': 'pakistani',
        'cooking_style': 'easy_to_cook',
        'local_ingredients': true,
        'traditional_dishes': true,
        'spice_level': 'moderate',
        'meal_preferences': {
          'breakfast': 'pakistani_style',
          'lunch': 'pakistani_style', 
          'dinner': 'pakistani_style',
          'snacks': 'pakistani_style'
        },
      };
      final reqRes = await _ai.createRequest(requestPayload);
      final int? requestId = int.tryParse('${reqRes['id'] ?? reqRes['request_id'] ?? (reqRes['data']?['id'] ?? reqRes['data']?['request_id'] ?? '')}');
      // If backend doesn't return an id, proceed without it (meals endpoint may accept optional request_id)
      if (requestId == null) {
        // keep going; generated endpoint will work if DB constraint relaxed
      }

      final String date0 = fmt(start);
      // Let AI decide the plan duration based on weight loss goal
      // For 65kg to 58kg (7kg loss), AI should create a 12-16 week plan
      final int totalDays = _calculateOptimalPlanDuration(weight, form['goal']?.toString() ?? '');
      print('=== PLAN DURATION CALCULATION ===');
      print('Current weight: $weight kg');
      print('Goal: ${form['goal']?.toString()}');
      print('AI calculated plan duration: $totalDays days (${(totalDays / 30).toStringAsFixed(1)} months)');
      print('================================');
      
      // Get user's training data to enhance nutrition plan
      final trainingData = _getUserTrainingData();
      // Training data integration debug (reduced for web compatibility)
      if (trainingData['has_training'] == true) {
        print('Training integration: ${trainingData['training_intensity']} intensity, ${trainingData['avg_training_minutes']} min/day');
      } else {
        print('Training integration: No active training detected');
      }

      // Calculate personalized daily nutrition based on user's height, weight, goal, and training
      final double bmr = _calculateBMR(weight, height, age, gender);
      
      // Adjust activity multiplier based on training data
      double activityMultiplier = 1.2; // Sedentary baseline
      if (trainingData['has_training']) {
        final intensity = trainingData['training_intensity'] as String;
        final avgMinutes = trainingData['avg_training_minutes'] as int;
        
        if (intensity == 'high' || avgMinutes >= 90) {
          activityMultiplier = 1.8; // Very active
        } else if (intensity == 'moderate' || avgMinutes >= 60) {
          activityMultiplier = 1.6; // Moderately active
        } else if (avgMinutes >= 30) {
          activityMultiplier = 1.4; // Lightly active
        } else {
          activityMultiplier = 1.3; // Light activity
        }
      }
      
      final double tdee = bmr * activityMultiplier;
      
      // Adjust calories based on weight loss goal and training intensity
      double calorieDeficit = 500; // Default deficit
      if (trainingData['has_training']) {
        final intensity = trainingData['training_intensity'] as String;
        if (intensity == 'high') {
          calorieDeficit = 400; // Smaller deficit for high-intensity training
        } else if (intensity == 'moderate') {
          calorieDeficit = 500; // Standard deficit
        } else {
          calorieDeficit = 600; // Larger deficit for low-intensity training
        }
      }
      
      final double targetDailyCalories = tdee - calorieDeficit;
      
      // Adjust macro distribution based on training
      double proteinRatio = 0.30; // Default 30% protein
      double carbRatio = 0.45; // Default 45% carbs
      double fatRatio = 0.25; // Default 25% fat
      
      if (trainingData['has_training']) {
        final intensity = trainingData['training_intensity'] as String;
        if (intensity == 'high') {
          proteinRatio = 0.35; // Higher protein for high-intensity training
          carbRatio = 0.40; // Higher carbs for energy
          fatRatio = 0.25;
        } else if (intensity == 'moderate') {
          proteinRatio = 0.32; // Moderate protein increase
          carbRatio = 0.43;
          fatRatio = 0.25;
        }
      }
      
      // Calculate macro distribution
      final double dailyProteins = (targetDailyCalories * proteinRatio) / 4; // 4 cal/g protein
      final double dailyCarbs = (targetDailyCalories * carbRatio) / 4; // 4 cal/g carbs  
      final double dailyFats = (targetDailyCalories * fatRatio) / 9; // 9 cal/g fat
      
      // Let AI generate the complete meal plan - NO hardcoded meals
      // AI will create personalized meal plans based on user preferences
      final List<Map<String, dynamic>> items = [];
      
      // Calculate totals for the entire plan
      final double totalCalories = targetDailyCalories * totalDays;
      final double totalProteins = dailyProteins * totalDays;
      final double totalFats = dailyFats * totalDays;
      final double totalCarbs = dailyCarbs * totalDays;
      
      print('Generated meal plan totals:');
      print('User: ${height}cm, ${weight}kg, ${age}yo, $gender');
      print('BMR: ${bmr.toStringAsFixed(0)}, TDEE: ${tdee.toStringAsFixed(0)}');
      print('Target Daily Calories: ${targetDailyCalories.toStringAsFixed(0)}');
      print('Total Days: $totalDays');
      print('Daily Protein: ${dailyProteins.toStringAsFixed(1)}g');
      print('Daily Fats: ${dailyFats.toStringAsFixed(1)}g');
      print('Daily Carbs: ${dailyCarbs.toStringAsFixed(1)}g');
      print('Total Items: ${items.length}');
      
      final payload = {
        if (requestId != null) 'request_id': requestId,
        'user_id': userId,
        // Send all category aliases so backend can accept any
        'meal_category': apiCategoryLabel(),
        'menu_plan_category': apiCategoryLabel(),
        'meal_plan_category': apiCategoryLabel(),
        'menu_plan': apiCategoryLabel(),
        'start_date': fmt(start),
        'end_date': fmt(end),
        'name': user?.name,
        'email': user?.email,
        'contact': user?.phone,
        'description': 'AI generated ${apiCategoryLabel()} plan for Gym Workouts (No Pork) - Target: ${weight}kg to ${int.tryParse(form['goal']?.toString().replaceAll(RegExp(r'[^\d]'), '') ?? '58') ?? 58}kg. Create personalized Pakistani meal plans with traditional dishes like daal, roti, chicken curry, biryani, keema, paneer tikka, fish curry, etc. Ensure meals are gym-optimized with proper protein, carb, and fat distribution. Training data: ${trainingData['has_training'] ? 'Active training (${trainingData['training_intensity']} intensity, ${trainingData['avg_training_minutes']} min/day, ${trainingData['workout_frequency']})' : 'No active training'}',
        'total_calories': totalCalories,
        'total_proteins': totalProteins,
        'total_fats': totalFats,
        'total_carbs': totalCarbs,
        'total_days': totalDays,
        'approval_status': 'PENDING',
        // Let AI generate all meal items - no hardcoded items
        // 'items': items,
        // Gym-specific requirements
        'activity_level': 'high',
        'workout_frequency': '5-6_days_per_week',
        'workout_type': 'strength_training',
        'fitness_goal': apiCategoryLabel().toLowerCase().contains('weight') ? 'fat_loss' : 'muscle_gain',
        'training_schedule': 'gym_based',
        'pre_workout_nutrition': true,
        'post_workout_nutrition': true,
        'recovery_focus': true,
        'gym_friendly': true,
        'meal_timing': 'workout_optimized',
        'protein_timing': 'peri_workout',
        // Dietary restrictions for AI meal generation
        'dietary_restrictions': ['no_pork', 'no_pork_products'],
        'excluded_foods': ['pork', 'bacon', 'ham', 'sausage', 'pork_chops', 'pork_tenderloin', 'pork_shoulder', 'pork_belly'],
        'religious_dietary': 'halal',
        'preferences': {
          'no_pork': true,
          'halal_compliant': true,
          'gym_optimized': true,
          'high_protein': true,
          'workout_timing': true,
          'pakistani_cuisine': true,
          'easy_cooking': true,
          'local_ingredients': true,
          'traditional_dishes': true,
          'meal_variety': true,
          'nutritional_balance': true,
          'alternative_proteins': ['chicken', 'beef', 'fish', 'lamb', 'turkey', 'eggs', 'dairy', 'whey_protein', 'casein_protein', 'daal', 'chana', 'paneer'],
          'training_data': trainingData,
          'ai_instructions': 'Generate unique Pakistani meal plans for each day. Use traditional dishes like daal, roti, chicken curry, biryani, keema, paneer tikka, fish curry, aloo gosht, chana masala, etc. Ensure each meal has proper nutritional values and varies daily. Focus on gym-friendly, high-protein options while maintaining Pakistani culinary traditions. ${trainingData['has_training'] ? 'User has active training: ${trainingData['training_intensity']} intensity, ${trainingData['avg_training_minutes']} minutes per day, ${trainingData['workout_frequency']} frequency. Adjust meal timing and protein distribution accordingly.' : 'User has no active training - focus on general fitness nutrition.'}'
        },
      };
      lastAiPayload.value = payload;
      Map<String, dynamic> res;
      try {
        res = await _ai.createGeneratedPlan(payload);
      } on Exception catch (e) {
        final msg = e.toString();
        if (msg.contains('413') || msg.contains('request entity too large')) {
          // Fallback: try creating plan with minimized payload (no totals either)
          final minimal = Map<String, dynamic>.from(payload);
          minimal.remove('total_calories');
          minimal.remove('total_proteins');
          minimal.remove('total_fats');
          minimal.remove('total_carbs');
          res = await _ai.createGeneratedPlan(minimal);
        } else {
          rethrow;
        }
      }
      
      // Parse returned plan data from AI backend
      final Map<String, dynamic> root = Map<String, dynamic>.from(res);
      final Map<String, dynamic> data = Map<String, dynamic>.from(root['data'] ?? root);
      
      // AI will generate all meal items automatically via OpenAI
      final createdId = data['id'] ?? root['id'];
      if (createdId != null) {
        print('AI plan created with ID: $createdId');
        print('AI plan created: ${height}cm, ${weight}kg, ${targetDailyCalories.toStringAsFixed(0)} cal/day');
        print('Training: ${trainingData['has_training'] ? '${trainingData['training_intensity']} intensity' : 'none'}');
        
        // Show user notification about OpenAI status
        if (AppConfig.openAIApiKey.isEmpty) {
          Get.snackbar(
            'Plan Created',
            'Basic meal plan created. For AI-generated personalized meals, configure OpenAI API key.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
          );
        } else {
          Get.snackbar(
            'AI Plan Created',
            'Personalized meal plan generated with AI!',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        }
      }
      aiGeneratedPlan.value = null;
      aiStatus.value = AIPlanStatus.draft;
      // Refresh the list of generated plans from backend
      await loadGeneratedPlansFromBackend();
    } finally {
      aiLoading.value = false;
    }
  }

  // Map generated items to approval payload and send
  Future<void> sendGeneratedPlanForApproval({required MealPlan plan, required String menuPlanCategory}) async {
    aiLoading.value = true;
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      final List<Map<String, dynamic>> items = [];
      for (final d in plan.days) {
        items.addAll(d.breakfast.map((m) => {
              'meal_type': 'Breakfast',
              'food_item_name': m.name,
              'grams': m.grams,
              'protein': m.proteinGrams,
              'fats': m.fatGrams,
              'carbs': m.carbsGrams,
              'calories': m.calories,
            }));
        items.addAll(d.lunch.map((m) => {
              'meal_type': 'Lunch',
              'food_item_name': m.name,
              'grams': m.grams,
              'protein': m.proteinGrams,
              'fats': m.fatGrams,
              'carbs': m.carbsGrams,
              'calories': m.calories,
            }));
        items.addAll(d.dinner.map((m) => {
              'meal_type': 'Dinner',
              'food_item_name': m.name,
              'grams': m.grams,
              'protein': m.proteinGrams,
              'fats': m.fatGrams,
              'carbs': m.carbsGrams,
              'calories': m.calories,
            }));
      }
      final approvalPayload = {
        'user_id': user?.id ?? 1,
        'name': user?.name,
        'email': user?.email,
        'contact': user?.phone,
        'menu_plan_category': menuPlanCategory,
        'total_days': plan.days.length,
        'description': 'Please review AI generated meal plan',
        'food_items': items,
      };
      await _ai.sendApprovalFoodMenu(approvalPayload);
      aiStatus.value = AIPlanStatus.pendingApproval;
    } finally {
      aiLoading.value = false;
    }
  }

  PlanCategory categoryFromString(String value) {
    final v = value.toLowerCase();
    if (v.contains('muscle')) return PlanCategory.muscleGain;
    return PlanCategory.weightLoss;
  }

  Future<void> _saveAiCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plan = aiGeneratedPlan.value;
      final status = aiStatus.value.name;
      if (plan != null) {
        final json = {
          'id': plan.id,
          'title': plan.title,
          'category': plan.category.name,
          'note': plan.note,
          'days': plan.days
              .map((d) => {
                    'day': d.dayNumber,
                    'breakfast': d.breakfast
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                    'lunch': d.lunch
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                    'dinner': d.dinner
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                  })
              .toList(),
        };
        await prefs.setString('ai_meal_plan_cache', jsonEncode({'plan': json, 'status': status}));
      }
    } catch (_) {}
  }

  Future<void> _loadCachedAiPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ai_meal_plan_cache');
      if (raw == null || raw.isEmpty) return;
      final parsed = jsonDecode(raw);
      final plan = parsed['plan'];
      final days = List<DayMeals>.from((plan['days'] as List).map((d) => DayMeals(
            dayNumber: d['day'] ?? 1,
            breakfast: List<MealItem>.from((d['breakfast'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
            lunch: List<MealItem>.from((d['lunch'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
            dinner: List<MealItem>.from((d['dinner'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
          )));
      aiGeneratedPlan.value = MealPlan(
        id: plan['id'],
        title: plan['title'],
        category: categoryFromString(plan['category'] ?? ''),
        note: plan['note'] ?? '',
        days: days,
      );
      final statusStr = (parsed['status'] ?? 'draft').toString();
      aiStatus.value = AIPlanStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => AIPlanStatus.draft,
      );
    } catch (_) {}
  }

  Future<void> loadGeneratedPlansFromBackend() async {
    try {
      print('Loading generated plans from backend...');
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      print('User ID: ${user?.id}');
      if (user?.id == null) {
        print('No user ID found - using default user ID');
        // Use a default user ID if profile is not loaded
        final defaultUserId = 1;
        final plans = await _ai.listGeneratedPlans(userId: defaultUserId);
        generatedPlans.assignAll(plans.cast<Map<String, dynamic>>());
        return;
      }

      final plans = await _ai.listGeneratedPlans(userId: user!.id);
      print('Fetched ${plans.length} plans from backend');
      print('Plans data: $plans');
      generatedPlans.value = List<Map<String, dynamic>>.from(plans);
      print('Updated generatedPlans list with ${generatedPlans.length} items');
    } catch (e) {
      print('Error loading generated plans: $e');
    }
  }

  Future<Map<String, dynamic>> getGeneratedPlanDetails(String planId) async {
    try {
      print('Loading plan details for ID: $planId');
      final details = await _ai.getGeneratedPlan(planId);
      print('Plan details loaded: $details');
      return details;
    } catch (e) {
      print('Error loading plan details: $e');
      rethrow;
    }
  }

  Future<void> deleteGeneratedPlan(String planId) async {
    try {
      aiLoading.value = true;
      await _ai.deleteGeneratedPlan(planId);
      await loadGeneratedPlansFromBackend();
    } finally {
      aiLoading.value = false;
    }
  }

  Future<void> sendAiPlanForApproval({required Map<String, dynamic> form}) async {
    aiLoading.value = true;
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      
      // Use default user ID if profile is not loaded
      final userId = user?.id ?? 1;
      if (user?.id == null) {
        print('User ID not available - using default user ID: $userId');
      }
      int? _toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is double) return v.round();
        return int.tryParse(v.toString());
      }
      // Compute default date range (30 days) if not provided
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final DateTime start = () {
        final s = form['start_date']?.toString();
        if (s != null && s.isNotEmpty) {
          try { return DateTime.parse(s); } catch (_) {}
        }
        return DateTime.now();
      }();
      final DateTime end = () {
        final e = form['end_date']?.toString();
        if (e != null && e.isNotEmpty) {
          try { return DateTime.parse(e); } catch (_) {}
        }
        return start.add(const Duration(days: 30));
      }();
      final payload = {
        'type': 'nutrition',
        'menu_plan': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        // Send alternate key some backends expect
        'meal_category': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        'age': _toInt(form['age']) ?? 0,
        'height_cm': _toInt(form['height']) ?? 0,
        'weight_kg': _toInt(form['weight']) ?? 0,
        'illness': form['illness']?.toString() ?? '',
        'gender': form['gender']?.toString() ?? '',
        'country': form['country']?.toString() ?? '',
        'goal': form['goal']?.toString() ?? '',
        'user_id': userId,
        'start_date': fmt(start),
        'end_date': fmt(end),
        // Keep nested user for display/backward compatibility
        'user': {
          'id': userId,
          'name': user?.name,
          'phone': user?.phone,
        },
      };
      lastAiPayload.value = payload;
      if (AppConfig.useAiRequests) {
        await _ai.createRequest(payload);
      } else {
        await _ai.createRequest(payload); // send to backend queue by default
      }
      aiStatus.value = AIPlanStatus.pendingApproval;
    } catch (_) {
      rethrow;
    } finally {
      aiLoading.value = false;
    }
  }

  void setApprovedByPortal() {
    aiStatus.value = AIPlanStatus.approved;
    if (aiGeneratedPlan.value != null) {
      assignPlan(aiGeneratedPlan.value!);
    }
  }
}

extension on DayMeals {
  DayMeals copyWith({int? dayNumber, List<MealItem>? breakfast, List<MealItem>? lunch, List<MealItem>? dinner}) {
    return DayMeals(
      dayNumber: dayNumber ?? this.dayNumber,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      dinner: dinner ?? this.dinner,
    );
  }
}


