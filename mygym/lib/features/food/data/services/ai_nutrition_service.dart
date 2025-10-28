import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

/// Custom exception for Gemini AI errors with structured error handling
class GeminiAIException implements Exception {
  final String errorCode;
  final String errorMessage;
  final int? retryAfter; // seconds

  const GeminiAIException({
    required this.errorCode,
    required this.errorMessage,
    this.retryAfter,
  });

  @override
  String toString() {
    return 'GeminiAIException: $errorCode - $errorMessage${retryAfter != null ? ' (retry after ${retryAfter}s)' : ''}';
  }

  /// Check if this is a service unavailable error
  bool get isServiceUnavailable => errorCode == 'SERVICE_UNAVAILABLE';

  /// Check if this is a generation failed error
  bool get isGenerationFailed => errorCode == 'GENERATION_FAILED';

  /// Check if this is a payload too large error
  bool get isPayloadTooLarge => errorCode == 'PAYLOAD_TOO_LARGE';
  
  /// Check if this is a timeout error
  bool get isTimeout => errorCode == 'TIMEOUT';
}

class AiNutritionService {
  final AuthService _auth = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  // Create an AI plan REQUEST for backend processing/approval (legacy)
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    // Prefer meals-specific requests endpoint to satisfy FK in generated table
    final endpoints = ['/api/appAIMeals/requests', '/api/appAIPlans/requests'];
    DioException? lastError;
    for (final ep in endpoints) {
      try {
        final res = await dio.post(ep, data: payload);
    if (res.statusCode == 200 || res.statusCode == 201) {
          return Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
        }
      } on DioException catch (e) {
        lastError = e;
        continue; // try next endpoint
      }
    }
    final data = lastError?.response?.data;
    throw Exception('AI request failed: ${data ?? lastError?.message ?? 'unknown error'}');
  }

  // Create generated meal plan using Gemini AI (NEW ENDPOINT)
  Future<Map<String, dynamic>> createGeneratedPlan(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    
    // Set longer timeout for AI requests
    dio.options.receiveTimeout = const Duration(seconds: 90);
    
    try {
      print('🤖 Using Gemini AI for meal plan generation via new endpoint');
      print('🤖 Payload: $payload');
      
      // Use the new Gemini AI endpoint
      final res = await dio.post('/api/appAIMeals/generated/ai', data: payload);
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        print('✅ Gemini AI meal plan creation successful - Status: ${res.statusCode}');
        print('🔍 Raw response data: ${res.data}');
        print('🔍 Response data type: ${res.data.runtimeType}');
        
        final result = Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
        
        // Check for structured error response from backend
        if (result['success'] == false) {
          final errorCode = result['error_code'] ?? 'UNKNOWN_ERROR';
          final errorMessage = result['error'] ?? 'Unknown error occurred';
          print('❌ Backend returned error: $errorCode - $errorMessage');
          
          // Create structured error for the controller to handle
          throw GeminiAIException(
            errorCode: errorCode,
            errorMessage: errorMessage,
            retryAfter: result['retry_after'],
          );
        }
        
        print('✅ Gemini AI meal plan created successfully');
        print('🔍 Processed result: $result');
        print('🔍 Result keys: ${result.keys.toList()}');
        
        // Check if we have a plan ID
        final planId = result['id'] ?? result['data']?['id'];
        print('🔍 Created plan ID: $planId');
        
        return result;
      }
      throw Exception('Failed to create Gemini AI meal plan: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      print('❌ Gemini AI meal plan creation failed: $e');
      print('❌ Status: $status, Data: $data');
      
      // Handle structured error responses from backend
      if (data is Map && data.containsKey('success') && data['success'] == false) {
        final errorCode = data['error_code'] ?? 'UNKNOWN_ERROR';
        final errorMessage = data['error'] ?? 'Unknown error occurred';
        print('❌ Structured error from backend: $errorCode - $errorMessage');
        
        throw GeminiAIException(
          errorCode: errorCode,
          errorMessage: errorMessage,
          retryAfter: data['retry_after'],
        );
      }
      
      // Handle HTTP status codes
      if (status == 413) {
        throw GeminiAIException(
          errorCode: 'PAYLOAD_TOO_LARGE',
          errorMessage: 'Request payload is too large. Please reduce the data size.',
        );
      } else if (status == 502 || status == 503 || status == 504) {
        throw GeminiAIException(
          errorCode: 'SERVICE_UNAVAILABLE',
          errorMessage: 'Try again later. Server is under repair.',
          retryAfter: 300,
        );
      }
      
      // Handle timeout specifically
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        throw GeminiAIException(
          errorCode: 'TIMEOUT',
          errorMessage: 'AI meal plan generation is taking longer than expected. Please try again in a few minutes.',
          retryAfter: 300, // 5 minutes
        );
      }
      
      // Generic error handling
      final errorMessage = data is String ? data : (data is Map ? data['message'] ?? data['error'] ?? data.toString() : e.message);
      throw GeminiAIException(
        errorCode: 'GENERATION_FAILED',
        errorMessage: 'Failed to generate AI meal plan: $errorMessage',
      );
    }
  }

  // Legacy method for backward compatibility (now uses Gemini AI)
  Future<Map<String, dynamic>> createGeneratedPlanLegacy(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    try {
      // If no items provided, generate via local AI first to create a full plan
      Map<String, dynamic> toSend = payload;
      final items = (payload['items'] is List) ? payload['items'] as List : const [];
      if (items.isEmpty) {
        // Extract training data from preferences
        final preferences = payload['preferences'] as Map<String, dynamic>? ?? {};
        final trainingData = preferences['training_data'] as Map<String, dynamic>? ?? {};
        
        // Use local AI for meal plan generation
        print('🤖 Using local AI for meal plan generation (legacy)');
        final gen = await _generateMealPlanWithLocalAI(
              userId: payload['user_id'] ?? 0,
              mealPlan: payload['meal_plan_category']?.toString() ?? payload['meal_category']?.toString() ?? 'Weight Loss',
              startDate: payload['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
              endDate: payload['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first,
              age: payload['age'] ?? 25,
              heightCm: payload['height_cm'] ?? 170,
              weightKg: payload['weight_kg'] ?? 70,
              gender: payload['gender']?.toString() ?? 'male',
              futureGoal: payload['future_goal']?.toString() ?? payload['goal']?.toString() ?? 'lose weight',
              country: payload['country']?.toString() ?? 'Pakistan',
              totalDays: payload['total_days'] ?? 30,
              targetDailyCalories: (payload['total_calories'] ?? 1800) / (payload['total_days'] ?? 30),
              dailyProteins: (payload['total_proteins'] ?? 150) / (payload['total_days'] ?? 30),
              dailyCarbs: (payload['total_carbs'] ?? 200) / (payload['total_days'] ?? 30),
              dailyFats: (payload['total_fats'] ?? 60) / (payload['total_days'] ?? 30),
              trainingData: trainingData,
          originalPayload: payload,
          );
          toSend = gen;
      }
      
      final res = await dio.post('/api/appAIMeals/generated', data: toSend);
    if (res.statusCode == 200 || res.statusCode == 201) {
        final result = Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
        
        // Extract the plan ID from the response
        final planId = result['id'] ?? result['data']?['id'];
        print('🔍 Created plan with ID: $planId');
        
        // Save individual meal items to the database
        if (planId != null && toSend.containsKey('items')) {
          final items = toSend['items'] as List;
          if (items.isNotEmpty) {
            print('🔍 Saving ${items.length} meal items to database');
            try {
              await _saveMealItemsToDatabase(dio, planId, items);
              print('✅ Successfully saved meal items to database');
            } catch (e) {
              print('⚠️ Error saving meal items to database: $e');
              // Don't throw error here - plan was created successfully
            }
          } else {
            print('⚠️ No meal items to save to database');
          }
        } else {
          print('⚠️ Cannot save meal items - missing plan ID or items');
        }
        
        return result;
      }
      throw Exception('Failed to create generated meal plan: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 413) {
        throw Exception('Generated plan 413: request entity too large');
      }
      throw Exception('Generated plan 400: ${data is String ? data : (data is Map ? data['message'] ?? data['error'] ?? data.toString() : e.message)}');
    }
  }


  Future<Map<String, dynamic>> getGeneratedPlan(dynamic id) async {
    final dio = await _authedDio();
    print('🔍 Fetching plan details for ID: $id');
    
    // Try to get plan with items included
    final res = await dio.get('/api/appAIMeals/generated/$id', queryParameters: {
      'include_items': true,
      'include_meals': true,
    });
    print('🔍 Backend response status: ${res.statusCode}');
    print('🔍 Backend response data: ${res.data}');
    
    if (res.statusCode == 200) {
      final result = Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
      print('🔍 Processed result keys: ${result.keys.toList()}');
      
      // If no items found, try alternative endpoint
      if (!result.containsKey('items') && !result.containsKey('data')) {
        print('🔍 No items found in main response, trying alternative endpoint...');
        try {
          final itemsRes = await dio.get('/api/appAIMeals/generated/$id/items');
          if (itemsRes.statusCode == 200) {
            print('🔍 Items response: ${itemsRes.data}');
            result['items'] = itemsRes.data;
          }
        } catch (e) {
          print('⚠️ Alternative items endpoint failed: $e');
        }
      }
      
      return result;
    }
    throw Exception('Failed to fetch generated meal plan: HTTP ${res.statusCode}');
  }

  Future<List<dynamic>> listGeneratedPlans({int? userId}) async {
    final dio = await _authedDio();
    print('🔍 AI Service - Listing generated plans for user: $userId');
    print('🔍 AI Service - Endpoint: /api/appAIMeals/generated');
    
    final res = await dio.get('/api/appAIMeals/generated', queryParameters: {
      if (userId != null) 'user_id': userId,
    });
    
    print('🔍 AI Service - Response status: ${res.statusCode}');
    print('🔍 AI Service - Response data: ${res.data}');
    
    if (res.statusCode == 200) {
      final data = res.data;
      print('🔍 AI Service - Data type: ${data.runtimeType}');
      
      if (data is List) {
        print('🔍 AI Service - Data is List with ${data.length} items');
        return data;
      }
      if (data is Map && data['data'] is List) {
        final list = List<dynamic>.from(data['data']);
        print('🔍 AI Service - Data is Map with data key containing ${list.length} items');
        return list;
      }
      if (data is Map && data['items'] is List) {
        final list = List<dynamic>.from(data['items']);
        print('🔍 AI Service - Data is Map with items key containing ${list.length} items');
        return list;
      }
      print('⚠️ AI Service - No valid list found in response, returning empty list');
      return [];
    }
    print('❌ AI Service - Request failed with status: ${res.statusCode}');
    throw Exception('Failed to list generated meal plans');
  }

  Future<void> deleteGeneratedPlan(dynamic id) async {
    final dio = await _authedDio();
    final res = await dio.delete('/api/appAIMeals/generated/$id');
    if (res.statusCode != 200) {
      throw Exception('Failed to delete generated meal plan: HTTP ${res.statusCode}');
    }
  }

  Future<void> uploadGeneratedItems({required dynamic planId, required List<Map<String, dynamic>> items, int chunkSize = 200}) async {
    if (items.isEmpty) return;
    final dio = await _authedDio();
    // Ensure each item has plan_id
    final normalized = items.map((it) {
      final m = Map<String, dynamic>.from(it);
      m['plan_id'] = planId;
      return m;
    }).toList();

    // Try multiple possible endpoints to avoid 404s in different backends
    final endpoints = <String>[
      // Prefer the dedicated bulk endpoint the backend just added
      '/api/appAIMeals/items/bulk',
      // Fallbacks for older deployments
      '/api/appAIGeneratedMealPlanItems',
      '/api/appAIMeals/items',
      '/api/appAIMeals/generated/items',
    ];

    for (int i = 0; i < normalized.length; i += chunkSize) {
      final chunk = normalized.sublist(i, i + chunkSize > normalized.length ? normalized.length : i + chunkSize);
      DioException? lastErr;
      bool uploaded = false;
      for (final ep in endpoints) {
        try {
          final res = await dio.post(ep, data: {'items': chunk});
          if (res.statusCode == 200 || res.statusCode == 201) {
            uploaded = true;
            break;
          }
        } on DioException catch (e) {
          // If 404, try next endpoint
          if (e.response?.statusCode == 404) {
            lastErr = e;
            continue;
          }
          rethrow;
        }
      }
      if (!uploaded) {
        final msg = lastErr?.response?.data ?? lastErr?.message ?? 'unknown error';
        throw Exception('Failed to upload items chunk: $msg');
      }
    }
  }

  // Send to approval_food_menu
  Future<Map<String, dynamic>> sendApprovalFoodMenu(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    try {
      final res = await dio.post('/api/approvalFoodMenu', data: payload);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
      }
      throw Exception('Failed to submit approval food menu: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception('Approval submit 400: ${data is String ? data : (data is Map ? data['message'] ?? data['error'] ?? data.toString() : e.message)}');
    }
  }

  Map<String, dynamic> _generateMockMealPlan(Map<String, dynamic> payload) {
    // This method should not be used anymore - all meal plans should be AI-generated
    throw Exception('Mock meal plans are disabled. Please use AI generation for personalized meal plans.');
  }

  /// Generate meal plan using local AI algorithms
  Future<Map<String, dynamic>> _generateMealPlanWithLocalAI({
    required int userId,
    required String mealPlan,
    required String startDate,
    required String endDate,
    required int age,
    required double heightCm,
    required double weightKg,
    required String gender,
    required String futureGoal,
    required String country,
    required int totalDays,
    required double targetDailyCalories,
    required double dailyProteins,
    required double dailyCarbs,
    required double dailyFats,
    required Map<String, dynamic> trainingData,
    Map<String, dynamic>? originalPayload,
  }) async {
    print('🤖 LOCAL AI: Starting meal plan generation');
    print('📊 TARGET: $targetDailyCalories cal/day, $dailyProteins g protein, $dailyCarbs g carbs, $dailyFats g fat');
    
    final items = <Map<String, dynamic>>[];
    final startDateObj = DateTime.parse(startDate);
    final goal = futureGoal.toLowerCase().contains('lose') || futureGoal.toLowerCase().contains('weight')
        ? 'weight_loss'
        : futureGoal.toLowerCase().contains('gain') || futureGoal.toLowerCase().contains('muscle')
        ? 'muscle_gain'
        : 'maintenance';
    
    // Get personalized food database based on user preferences and training data
    final foodDatabase = _getPersonalizedFoodDatabase(goal, country, trainingData);
    
    for (int day = 0; day < totalDays; day++) {
      final currentDate = startDateObj.add(Duration(days: day));
      final dateStr = currentDate.toIso8601String().split('T').first;
      
      // Generate meals for each day
      final meals = ['breakfast', 'lunch', 'dinner'];
      final mealRatios = [0.25, 0.40, 0.35]; // Breakfast, Lunch, Dinner calorie distribution
      
      for (int mealIndex = 0; mealIndex < meals.length; mealIndex++) {
        final mealType = meals[mealIndex];
        final ratio = mealRatios[mealIndex];
        
        // Calculate target nutrition for this meal
        final mealCalories = (targetDailyCalories * ratio).round();
        final mealProteins = (dailyProteins * ratio).round();
        final mealCarbs = (dailyCarbs * ratio).round();
        final mealFats = (dailyFats * ratio).round();
        
        // Use local AI to select optimal food
        try {
          final selectedFood = _selectOptimalFood(
            foodDatabase: foodDatabase,
            mealType: mealType,
            goal: goal,
            targetCalories: mealCalories,
            targetProteins: mealProteins,
            targetCarbs: mealCarbs,
            targetFats: mealFats,
            day: day,
            userPreferences: trainingData,
          );
          
          if (selectedFood != null) {
            print('🍽️ LOCAL AI: Selected food: ${selectedFood['name']}');
            
            // Create meal item with calculated nutrition values
            final mealItem = {
              'meal_type': mealType,
              'food_item_name': selectedFood['name'],
              'grams': selectedFood['grams'],
              'calories': selectedFood['calories'],
              'protein': selectedFood['protein'],
              'fat': selectedFood['fat'],
              'carbs': selectedFood['carbs'],
              'date': dateStr,
            };
            items.add(mealItem);
            print('🔍 Added meal item: $mealItem');
            print('✅ LOCAL AI: Added meal item: ${selectedFood['name']}');
          } else {
            print('⚠️ LOCAL AI: No suitable food found for $mealType - using fallback');
            // Use fallback food
            final fallbackFood = _getFallbackFood(mealType, goal);
            final mealItem = {
              'meal_type': mealType,
              'food_item_name': fallbackFood['name'],
              'grams': fallbackFood['grams'],
              'calories': fallbackFood['calories'],
              'protein': fallbackFood['protein'],
              'fat': fallbackFood['fat'],
              'carbs': fallbackFood['carbs'],
              'date': dateStr,
            };
            items.add(mealItem);
          }
        } catch (e) {
          print('⚠️ LOCAL AI Error: $e - using fallback for $mealType');
          // Use fallback food
          final fallbackFood = _getFallbackFood(mealType, goal);
          final mealItem = {
            'meal_type': mealType,
            'food_item_name': fallbackFood['name'],
            'grams': fallbackFood['grams'],
            'calories': fallbackFood['calories'],
            'protein': fallbackFood['protein'],
            'fat': fallbackFood['fat'],
            'carbs': fallbackFood['carbs'],
            'date': dateStr,
          };
          items.add(mealItem);
        }
      }
    }
    
    // Start with original payload if provided, otherwise create new structure
    final result = originalPayload != null ? Map<String, dynamic>.from(originalPayload) : <String, dynamic>{};
    
    // Add/update the generated meal plan data
    result['user_id'] = userId;
    result['start_date'] = startDate;
    result['end_date'] = endDate;
    result['meal_plan'] = mealPlan;
    result['meal_plan_category'] = mealPlan;
    result['total_days'] = totalDays;
    result['items'] = items;
    
    // Add calculated totals
    final totalCalories = items.fold<int>(0, (sum, item) => sum + (item['calories'] as int? ?? 0));
    final totalProteins = items.fold<int>(0, (sum, item) => sum + (item['protein'] as int? ?? 0));
    final totalCarbs = items.fold<int>(0, (sum, item) => sum + (item['carbs'] as int? ?? 0));
    final totalFats = items.fold<int>(0, (sum, item) => sum + (item['fat'] as int? ?? 0));
    
    result['total_calories'] = totalCalories;
    result['total_proteins'] = totalProteins;
    result['total_carbs'] = totalCarbs;
    result['total_fats'] = totalFats;
    
    print('🤖 LOCAL AI: Generated ${items.length} meal items for $totalDays days');
    print('📊 TOTALS: $totalCalories cal, $totalProteins g protein, $totalCarbs g carbs, $totalFats g fat');
    print('📋 MEAL PLAN DATA: ${result.toString()}');
    
    return result;
  }

  /// Estimate nutrition values for a food item based on its name and meal type
  Map<String, dynamic> _estimateNutritionForFood(String foodName, String mealType, int targetCalories) {
    // Base nutrition estimates based on meal type
    final baseNutrition = _getBaseNutritionForMealType(mealType);
    
    // Adjust based on food name keywords
    int calories = baseNutrition['calories'];
    int protein = baseNutrition['proteins'];
    int carbs = baseNutrition['carbs'];
    int fats = baseNutrition['fats'];
    int grams = baseNutrition['grams'];
    
    // Adjust based on food name keywords
    if (foodName.toLowerCase().contains('chicken') || foodName.toLowerCase().contains('turkey')) {
      protein += 15;
      calories += 50;
    }
    if (foodName.toLowerCase().contains('salmon') || foodName.toLowerCase().contains('fish')) {
      protein += 20;
      fats += 8;
      calories += 80;
    }
    if (foodName.toLowerCase().contains('eggs')) {
      protein += 12;
      fats += 10;
      calories += 70;
    }
    if (foodName.toLowerCase().contains('quinoa') || foodName.toLowerCase().contains('rice')) {
      carbs += 25;
      protein += 5;
      calories += 100;
    }
    if (foodName.toLowerCase().contains('oatmeal')) {
      carbs += 30;
      protein += 8;
      calories += 120;
    }
    if (foodName.toLowerCase().contains('avocado')) {
      fats += 15;
      calories += 80;
    }
    if (foodName.toLowerCase().contains('nuts') || foodName.toLowerCase().contains('almonds')) {
      fats += 12;
      protein += 6;
      calories += 90;
    }
    
    // Adjust serving size to match target calories
    final servingMultiplier = targetCalories / calories;
    grams = (grams * servingMultiplier).round();
    calories = (calories * servingMultiplier).round();
    protein = (protein * servingMultiplier).round();
    carbs = (carbs * servingMultiplier).round();
    fats = (fats * servingMultiplier).round();
    
    return {
      'grams': grams,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fats,
    };
  }

  /// Get base nutrition for meal type
  Map<String, dynamic> _getBaseNutritionForMealType(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return {
          'grams': 200,
          'calories': 350,
          'proteins': 15,
          'carbs': 45,
          'fats': 12,
        };
      case 'lunch':
        return {
          'grams': 300,
          'calories': 500,
          'proteins': 25,
          'carbs': 60,
          'fats': 15,
        };
      case 'dinner':
        return {
          'grams': 350,
          'calories': 450,
          'proteins': 30,
          'carbs': 40,
          'fats': 18,
        };
      default:
        return {
          'grams': 250,
          'calories': 400,
          'proteins': 20,
          'carbs': 50,
          'fats': 15,
        };
    }
  }

  /// Get personalized food database based on user preferences and goals
  Map<String, List<Map<String, dynamic>>> _getPersonalizedFoodDatabase(
    String goal, 
    String country, 
    Map<String, dynamic> trainingData
  ) {
    final baseFoods = _getBaseFoodDatabase();
    final personalizedFoods = <String, List<Map<String, dynamic>>>{};
    
    // Apply personalization based on user preferences
    for (final mealType in baseFoods.keys) {
      personalizedFoods[mealType] = List<Map<String, dynamic>>.from(baseFoods[mealType]!);
      
      // Adjust foods based on goal
      if (goal == 'weight_loss') {
        // Prioritize lower calorie, higher protein foods
        personalizedFoods[mealType]!.sort((a, b) {
          final aScore = (a['protein'] as int) - (a['calories'] as int) ~/ 10;
          final bScore = (b['protein'] as int) - (b['calories'] as int) ~/ 10;
          return bScore.compareTo(aScore);
        });
      } else if (goal == 'muscle_gain') {
        // Prioritize higher protein foods
        personalizedFoods[mealType]!.sort((a, b) {
          return (b['protein'] as int).compareTo(a['protein'] as int);
        });
      }
      
      // Apply cultural preferences based on country
      if (country.toLowerCase().contains('pakistan') || country.toLowerCase().contains('india')) {
        // Add regional foods
        personalizedFoods[mealType]!.addAll(_getRegionalFoods(mealType, 'south_asian'));
      }
    }
    
    return personalizedFoods;
  }

  /// Get base food database with comprehensive nutrition information
  Map<String, List<Map<String, dynamic>>> _getBaseFoodDatabase() {
    return {
      'breakfast': [
        {
          'name': 'Oatmeal with berries and honey',
          'calories': 320,
          'protein': 12,
          'carbs': 58,
          'fat': 6,
          'grams': 250,
          'category': 'grain',
          'preparation': 'cooked',
        },
        {
          'name': 'Greek yogurt with mixed nuts',
          'calories': 280,
          'protein': 20,
          'carbs': 15,
          'fat': 16,
          'grams': 200,
          'category': 'dairy',
          'preparation': 'raw',
        },
        {
          'name': 'Scrambled eggs with whole wheat toast',
          'calories': 350,
          'protein': 22,
          'carbs': 25,
          'fat': 18,
          'grams': 220,
          'category': 'protein',
          'preparation': 'cooked',
        },
        {
          'name': 'Protein smoothie with banana',
          'calories': 300,
          'protein': 25,
          'carbs': 35,
          'fat': 8,
          'grams': 300,
          'category': 'beverage',
          'preparation': 'blended',
        },
        {
          'name': 'Avocado toast with poached egg',
          'calories': 380,
          'protein': 18,
          'carbs': 30,
          'fat': 22,
          'grams': 200,
          'category': 'protein',
          'preparation': 'cooked',
        },
        {
          'name': 'Quinoa porridge with fruits',
          'calories': 290,
          'protein': 10,
          'carbs': 52,
          'fat': 5,
          'grams': 250,
          'category': 'grain',
          'preparation': 'cooked',
        },
      ],
      'lunch': [
        {
          'name': 'Grilled chicken salad with quinoa',
          'calories': 450,
          'protein': 35,
          'carbs': 40,
          'fat': 15,
          'grams': 350,
          'category': 'protein',
          'preparation': 'grilled',
        },
        {
          'name': 'Salmon with sweet potato and broccoli',
          'calories': 480,
          'protein': 38,
          'carbs': 45,
          'fat': 18,
          'grams': 400,
          'category': 'protein',
          'preparation': 'baked',
        },
        {
          'name': 'Turkey and avocado wrap',
          'calories': 420,
          'protein': 28,
          'carbs': 35,
          'fat': 20,
          'grams': 280,
          'category': 'protein',
          'preparation': 'wrapped',
        },
        {
          'name': 'Lentil curry with brown rice',
          'calories': 460,
          'protein': 22,
          'carbs': 70,
          'fat': 8,
          'grams': 400,
          'category': 'legume',
          'preparation': 'cooked',
        },
        {
          'name': 'Quinoa vegetable bowl',
          'calories': 380,
          'protein': 15,
          'carbs': 55,
          'fat': 12,
          'grams': 350,
          'category': 'grain',
          'preparation': 'cooked',
        },
        {
          'name': 'Grilled fish with mixed vegetables',
          'calories': 400,
          'protein': 32,
          'carbs': 20,
          'fat': 22,
          'grams': 350,
          'category': 'protein',
          'preparation': 'grilled',
        },
      ],
      'dinner': [
        {
          'name': 'Baked salmon with roasted vegetables',
          'calories': 420,
          'protein': 35,
          'carbs': 25,
          'fat': 20,
          'grams': 400,
          'category': 'protein',
          'preparation': 'baked',
        },
        {
          'name': 'Grilled chicken with quinoa pilaf',
          'calories': 450,
          'protein': 40,
          'carbs': 35,
          'fat': 15,
          'grams': 380,
          'category': 'protein',
          'preparation': 'grilled',
        },
        {
          'name': 'Lean beef stir-fry with brown rice',
          'calories': 480,
          'protein': 38,
          'carbs': 45,
          'fat': 18,
          'grams': 400,
          'category': 'protein',
          'preparation': 'stir-fried',
        },
        {
          'name': 'Baked cod with roasted sweet potato',
          'calories': 400,
          'protein': 30,
          'carbs': 40,
          'fat': 12,
          'grams': 350,
          'category': 'protein',
          'preparation': 'baked',
        },
        {
          'name': 'Grilled fish with steamed vegetables',
          'calories': 380,
          'protein': 32,
          'carbs': 20,
          'fat': 18,
          'grams': 350,
          'category': 'protein',
          'preparation': 'grilled',
        },
        {
          'name': 'Chicken and vegetable curry',
          'calories': 420,
          'protein': 28,
          'carbs': 35,
          'fat': 16,
          'grams': 400,
          'category': 'protein',
          'preparation': 'curried',
        },
      ],
    };
  }

  /// Get regional foods based on country/culture
  List<Map<String, dynamic>> _getRegionalFoods(String mealType, String region) {
    if (region == 'south_asian') {
      switch (mealType) {
        case 'breakfast':
          return [
            {
              'name': 'Paratha with yogurt',
              'calories': 350,
              'protein': 12,
              'carbs': 45,
              'fat': 14,
              'grams': 200,
              'category': 'grain',
              'preparation': 'cooked',
            },
            {
              'name': 'Dal with rice',
              'calories': 320,
              'protein': 15,
              'carbs': 55,
              'fat': 6,
              'grams': 300,
              'category': 'legume',
              'preparation': 'cooked',
            },
          ];
        case 'lunch':
          return [
            {
              'name': 'Chicken biryani',
              'calories': 520,
              'protein': 25,
              'carbs': 65,
              'fat': 18,
              'grams': 400,
              'category': 'protein',
              'preparation': 'cooked',
            },
            {
              'name': 'Lamb curry with naan',
              'calories': 480,
              'protein': 30,
              'carbs': 45,
              'fat': 20,
              'grams': 400,
              'category': 'protein',
              'preparation': 'curried',
            },
          ];
        case 'dinner':
          return [
            {
              'name': 'Fish curry with rice',
              'calories': 450,
              'protein': 28,
              'carbs': 50,
              'fat': 16,
              'grams': 400,
              'category': 'protein',
              'preparation': 'curried',
            },
            {
              'name': 'Vegetable biryani',
              'calories': 400,
              'protein': 12,
              'carbs': 70,
              'fat': 12,
              'grams': 400,
              'category': 'vegetable',
              'preparation': 'cooked',
            },
          ];
      }
    }
    return [];
  }

  /// Select optimal food using local AI algorithms
  Map<String, dynamic>? _selectOptimalFood({
    required Map<String, List<Map<String, dynamic>>> foodDatabase,
    required String mealType,
    required String goal,
    required int targetCalories,
    required int targetProteins,
    required int targetCarbs,
    required int targetFats,
    required int day,
    required Map<String, dynamic> userPreferences,
  }) {
    final availableFoods = foodDatabase[mealType] ?? [];
    if (availableFoods.isEmpty) return null;

    // Calculate fitness scores for each food
    final scoredFoods = availableFoods.map((food) {
      final score = _calculateFoodFitnessScore(
        food: food,
        targetCalories: targetCalories,
        targetProteins: targetProteins,
        targetCarbs: targetCarbs,
        targetFats: targetFats,
        goal: goal,
        day: day,
        userPreferences: userPreferences,
      );
      return {
        'food': food,
        'score': score,
      };
    }).toList();

    // Sort by score (highest first)
    scoredFoods.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // Add some variety by occasionally selecting from top 3 foods
    final topFoods = scoredFoods.take(3).toList();
    final selectedIndex = day % topFoods.length;
    final selectedFood = topFoods[selectedIndex]['food'] as Map<String, dynamic>;

    // Adjust serving size to better match targets
    return _adjustServingSize(selectedFood, targetCalories, targetProteins, targetCarbs, targetFats);
  }

  /// Calculate fitness score for a food item
  double _calculateFoodFitnessScore({
    required Map<String, dynamic> food,
    required int targetCalories,
    required int targetProteins,
    required int targetCarbs,
    required int targetFats,
    required String goal,
    required int day,
    required Map<String, dynamic> userPreferences,
  }) {
    double score = 0.0;

    // Calorie match (40% weight)
    final calorieDiff = ((food['calories'] as int) - targetCalories).abs();
    final calorieScore = 1.0 - (calorieDiff / targetCalories);
    score += calorieScore * 0.4;

    // Protein match (30% weight)
    final proteinDiff = ((food['protein'] as int) - targetProteins).abs();
    final proteinScore = 1.0 - (proteinDiff / (targetProteins + 1));
    score += proteinScore * 0.3;

    // Macro balance (20% weight)
    final carbDiff = ((food['carbs'] as int) - targetCarbs).abs();
    final fatDiff = ((food['fat'] as int) - targetFats).abs();
    final macroScore = 1.0 - ((carbDiff + fatDiff) / (targetCarbs + targetFats + 2));
    score += macroScore * 0.2;

    // Goal-specific adjustments (10% weight)
    if (goal == 'weight_loss') {
      // Prefer lower calorie density
      final calorieDensity = (food['calories'] as int) / (food['grams'] as int);
      if (calorieDensity < 2.0) score += 0.1;
    } else if (goal == 'muscle_gain') {
      // Prefer higher protein content
      final proteinDensity = (food['protein'] as int) / (food['grams'] as int);
      if (proteinDensity > 0.1) score += 0.1;
    }

    return score;
  }

  /// Adjust serving size to better match nutritional targets
  Map<String, dynamic> _adjustServingSize(
    Map<String, dynamic> food,
    int targetCalories,
    int targetProteins,
    int targetCarbs,
    int targetFats,
  ) {
    final currentCalories = food['calories'] as int;
    final currentProteins = food['protein'] as int;
    final currentCarbs = food['carbs'] as int;
    final currentFats = food['fat'] as int;
    final currentGrams = food['grams'] as int;

    // Calculate adjustment factor based on calorie target
    final calorieFactor = targetCalories / currentCalories;
    
    // Apply adjustment with some constraints
    final adjustedFactor = calorieFactor.clamp(0.5, 2.0);

    return {
      'name': food['name'],
      'calories': (currentCalories * adjustedFactor).round(),
      'protein': (currentProteins * adjustedFactor).round(),
      'carbs': (currentCarbs * adjustedFactor).round(),
      'fat': (currentFats * adjustedFactor).round(),
      'grams': (currentGrams * adjustedFactor).round(),
    };
  }

  /// Get fallback food when AI selection fails
  Map<String, dynamic> _getFallbackFood(String mealType, String goal) {
    final baseNutrition = _getBaseNutritionForMealType(mealType);
    
    String foodName;
    if (mealType == 'breakfast') {
      foodName = goal == 'weight_loss' ? 'Oatmeal with berries' : 'Protein smoothie';
    } else if (mealType == 'lunch') {
      foodName = goal == 'weight_loss' ? 'Grilled chicken salad' : 'Salmon with quinoa';
    } else {
      foodName = goal == 'weight_loss' ? 'Baked fish with vegetables' : 'Grilled chicken with rice';
    }

    return {
      'name': foodName,
      'calories': baseNutrition['calories'],
      'protein': baseNutrition['proteins'],
      'carbs': baseNutrition['carbs'],
      'fat': baseNutrition['fats'],
      'grams': baseNutrition['grams'],
    };
  }

  // This method is no longer needed - Local AI handles meal generation
  List<Map<String, dynamic>> _getMealItems(String mealType, String category) {
    throw Exception('This method is deprecated. Use local AI for meal generation.');
  }

  /// Save meal items to database in the correct format
  Future<void> _saveMealItemsToDatabase(Dio dio, dynamic planId, List<dynamic> items) async {
    final List<Map<String, dynamic>> dbItems = [];
    
    for (final item in items) {
      final itemMap = item as Map<String, dynamic>;
      dbItems.add({
        'plan_id': planId,
        'date': itemMap['date'] ?? DateTime.now().toIso8601String().split('T').first,
        'meal_type': itemMap['meal_type'] ?? 'breakfast',
        'food_item_name': itemMap['food_item_name'] ?? 'Food',
        'grams': itemMap['grams'] ?? 0,
        'calories': itemMap['calories'] ?? 0,
        'proteins': itemMap['protein'] ?? 0,
        'fats': itemMap['fat'] ?? 0,
        'carbs': itemMap['carbs'] ?? 0,
      });
    }
    
    print('🔍 Sending ${dbItems.length} items to database API');
    print('🔍 Sample item: ${dbItems.isNotEmpty ? dbItems.first : 'No items'}');
    
    final response = await dio.post('/api/appAIGeneratedMealPlanItems', data: {'items': dbItems});
    print('🔍 Database save response: ${response.statusCode} - ${response.data}');
  }

  Future<void> _saveMealItems(Dio dio, dynamic planId, Map<String, dynamic> planJson) async {
    final List<Map<String, dynamic>> items = [];
    final days = planJson['days'] as List? ?? [];
    
    for (int dayIndex = 0; dayIndex < days.length; dayIndex++) {
      final day = days[dayIndex];
      final date = _getDateForDay(dayIndex);
      
      // Process each meal type
      final meals = ['breakfast', 'lunch', 'dinner'];
      for (final mealType in meals) {
        final mealItems = day[mealType] as List? ?? [];
        for (final item in mealItems) {
          items.add({
            'plan_id': planId,
            'date': date,
            'meal_type': mealType,
            'food_item_name': item['name'] ?? 'Food',
            'grams': item['grams'] ?? 0,
            'calories': item['calories'] ?? 0,
            'proteins': item['protein'] ?? 0,
            'fats': item['fats'] ?? 0,
            'carbs': item['carbs'] ?? 0,
          });
        }
      }
    }
    
    if (items.isNotEmpty) {
      await dio.post('/api/appAIGeneratedMealPlanItems', data: {'items': items});
    }
  }

  String _getDateForDay(int dayIndex) {
    final startDate = DateTime.now();
    final targetDate = startDate.add(Duration(days: dayIndex));
    return targetDate.toIso8601String().split('T').first;
  }

  int _calculateTotalCalories(Map<String, dynamic> planJson) {
    int total = 0;
    final days = planJson['days'] as List? ?? [];
    for (final day in days) {
      for (final mealType in ['breakfast', 'lunch', 'dinner']) {
        final items = day[mealType] as List? ?? [];
        for (final item in items) {
          total += (item['calories'] as num? ?? 0).toInt();
        }
      }
    }
    return total;
  }

  int _calculateTotalProteins(Map<String, dynamic> planJson) {
    int total = 0;
    final days = planJson['days'] as List? ?? [];
    for (final day in days) {
      for (final mealType in ['breakfast', 'lunch', 'dinner']) {
        final items = day[mealType] as List? ?? [];
        for (final item in items) {
          total += (item['protein'] as num? ?? 0).toInt();
        }
      }
    }
    return total;
  }

  int _calculateTotalFats(Map<String, dynamic> planJson) {
    int total = 0;
    final days = planJson['days'] as List? ?? [];
    for (final day in days) {
      for (final mealType in ['breakfast', 'lunch', 'dinner']) {
        final items = day[mealType] as List? ?? [];
        for (final item in items) {
          total += (item['fats'] as num? ?? 0).toInt();
        }
      }
    }
    return total;
  }

  int _calculateTotalCarbs(Map<String, dynamic> planJson) {
    int total = 0;
    final days = planJson['days'] as List? ?? [];
    for (final day in days) {
      for (final mealType in ['breakfast', 'lunch', 'dinner']) {
        final items = day[mealType] as List? ?? [];
        for (final item in items) {
          total += (item['carbs'] as num? ?? 0).toInt();
        }
      }
    }
    return total;
  }
}


