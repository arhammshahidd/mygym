import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../../shared/services/openai_service.dart';

class AiNutritionService {
  final AuthService _auth = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  // Create an AI plan REQUEST for backend processing/approval
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    final res = await dio.post('/api/appAIPlans/requests', data: payload);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to create AI meal request');
  }

  // Generate meal plan via backend AI service
  Future<Map<String, dynamic>> createGenerated(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    
    // Use the existing requests endpoint to create AI plan
    final requestData = {
      'type': 'nutrition',
      'menu_plan': payload['menu_plan'] ?? payload['meal_category'],
      'meal_category': payload['menu_plan'] ?? payload['meal_category'],
      'age': payload['age'],
      'height_cm': payload['height_cm'],
      'weight_kg': payload['weight_kg'],
      'illness': payload['illness'] ?? '',
      'gender': payload['gender'],
      'country': payload['country'] ?? '',
      'goal': payload['goal'],
      'user_id': payload['user_id'],
      'start_date': payload['start_date'],
      'end_date': payload['end_date'],
      'user': {
        'id': payload['user_id'],
        'name': payload['user_name'] ?? 'User',
        'phone': payload['user_phone'] ?? '',
      },
    };
    
    final res = await dio.post('/api/appAIPlans/requests', data: requestData);
    if (res.statusCode == 200 || res.statusCode == 201) {
      final responseData = Map<String, dynamic>.from(res.data);
      
      // Generate a mock meal plan structure for the UI
      final mockPlanJson = _generateMockMealPlan(payload);
      
      return {
        'id': responseData['id'] ?? 'ai_request_${DateTime.now().millisecondsSinceEpoch}',
        'data': mockPlanJson,
        'request_data': requestData,
      };
    }
    throw Exception('Failed to create AI meal plan request');
  }

  Map<String, dynamic> _generateMockMealPlan(Map<String, dynamic> payload) {
    // Generate a simple 7-day meal plan structure for UI display
    final days = <Map<String, dynamic>>[];
    final mealCategory = payload['menu_plan'] ?? payload['meal_category'] ?? 'weightLoss';
    
    for (int day = 1; day <= 7; day++) {
      days.add({
        'day': day,
        'breakfast': _getMealItems('breakfast', mealCategory),
        'lunch': _getMealItems('lunch', mealCategory),
        'dinner': _getMealItems('dinner', mealCategory),
      });
    }
    
    return {
      'title': mealCategory == 'muscleGain' ? 'Mass Gain Plan' : 'Weight Loss Plan',
      'note': mealCategory == 'muscleGain' 
          ? 'Perfect for Muscle Building and recovery'
          : 'Balanced nutrition for healthy weight loss',
      'days': days,
    };
  }

  List<Map<String, dynamic>> _getMealItems(String mealType, String category) {
    final isMuscleGain = category == 'muscleGain';
    
    switch (mealType) {
      case 'breakfast':
        return isMuscleGain 
            ? [
                {'name': '6 Eggs', 'grams': 300, 'calories': 930, 'protein': 78, 'fats': 60, 'carbs': 7},
                {'name': 'Oatmeal', 'grams': 100, 'calories': 389, 'protein': 17, 'fats': 7, 'carbs': 66},
              ]
            : [
                {'name': 'Oatmeal with berries', 'grams': 150, 'calories': 250, 'protein': 8, 'fats': 4, 'carbs': 45},
                {'name': 'Greek Yogurt', 'grams': 200, 'calories': 170, 'protein': 15, 'fats': 5, 'carbs': 12},
              ];
      case 'lunch':
        return isMuscleGain
            ? [
                {'name': 'Chicken Breast', 'grams': 200, 'calories': 825, 'protein': 125, 'fats': 18, 'carbs': 0},
                {'name': 'Brown Rice', 'grams': 150, 'calories': 220, 'protein': 5, 'fats': 2, 'carbs': 45},
              ]
            : [
                {'name': 'Grilled Chicken', 'grams': 150, 'calories': 300, 'protein': 35, 'fats': 12, 'carbs': 0},
                {'name': 'Brown Rice', 'grams': 100, 'calories': 220, 'protein': 5, 'fats': 2, 'carbs': 45},
              ];
      case 'dinner':
        return isMuscleGain
            ? [
                {'name': 'Chicken Thighs', 'grams': 200, 'calories': 990, 'protein': 150, 'fats': 50, 'carbs': 0},
                {'name': 'Sweet Potato', 'grams': 200, 'calories': 180, 'protein': 4, 'fats': 0, 'carbs': 41},
              ]
            : [
                {'name': 'Salmon', 'grams': 150, 'calories': 320, 'protein': 30, 'fats': 20, 'carbs': 0},
                {'name': 'Mixed Salad', 'grams': 100, 'calories': 120, 'protein': 3, 'fats': 7, 'carbs': 12},
              ];
      default:
        return [];
    }
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


