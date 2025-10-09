import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../../shared/services/openai_service.dart';
import '../../../../shared/services/local_ai_service.dart';

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

  // Create generated meal plan (store plan + items)
  Future<Map<String, dynamic>> createGeneratedPlan(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    try {
      // If no items provided, generate via OpenAI first to create a full plan
      Map<String, dynamic> toSend = payload;
      final items = (payload['items'] is List) ? payload['items'] as List : const [];
      if (items.isEmpty) {
        // Extract training data from preferences
        final preferences = payload['preferences'] as Map<String, dynamic>? ?? {};
        final trainingData = preferences['training_data'] as Map<String, dynamic>? ?? {};
        
        // Use Local AI Service as primary (FREE) method, with OpenAI as optional enhancement
        try {
          if (AppConfig.openAIApiKey.isNotEmpty) {
            print('🤖 Using OpenAI for enhanced meal plan generation');
            final openAI = OpenAIService();
            final gen = await openAI.generateMealPlanJson(
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
            );
            toSend = gen;
          } else {
            throw Exception('OpenAI API key not configured - using free Local AI');
          }
        } catch (e) {
          print('🤖 Using FREE Local AI Service for meal plan generation: $e');
          // Primary method: Local AI Service (completely FREE)
          final localAI = LocalAIService();
          final gen = await localAI.generateMealPlanJson(
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
          );
          toSend = gen;
        }
      }
      
      final res = await dio.post('/api/appAIMeals/generated', data: toSend);
    if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
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
    final res = await dio.get('/api/appAIMeals/generated/$id');
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(res.data is Map ? res.data : {'data': res.data});
    }
    throw Exception('Failed to fetch generated meal plan');
  }

  Future<List<dynamic>> listGeneratedPlans({int? userId}) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appAIMeals/generated', queryParameters: {
      if (userId != null) 'user_id': userId,
    });
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) return data;
      if (data is Map && data['data'] is List) return List<dynamic>.from(data['data']);
      if (data is Map && data['items'] is List) return List<dynamic>.from(data['items']);
      return [];
    }
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

  // This method is no longer needed - Local AI Service handles meal generation
  List<Map<String, dynamic>> _getMealItems(String mealType, String category) {
    throw Exception('This method is deprecated. Use Local AI Service for meal generation.');
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


