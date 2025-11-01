import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class DailyTrainingService {
  final AuthService _authService = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  /// Get user's daily training plans
  /// Optional date parameter to get plans for specific date
  Future<List<Map<String, dynamic>>> getDailyPlans({String? date}) async {
    try {
      final dio = await _authedDio();
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['date'] = date;
      }
      
      final res = await dio.get('/api/dailyTraining/mobile/plans', queryParameters: queryParams);
      print('🔍 Daily Training Plans API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          final plans = data['data'] as List<dynamic>? ?? [];
          return plans.cast<Map<String, dynamic>>();
        } else if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      throw Exception('Failed to fetch daily training plans: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to access daily training plans');
        print('💡 This is likely a backend permissions issue. Using local data only.');
      }
      rethrow;
    }
  }

  /// Get specific daily training plan by ID
  Future<Map<String, dynamic>> getDailyPlan(int planId) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/dailyTraining/mobile/plans/$planId');
    print('🔍 Daily Training Plan API Response for ID $planId:');
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
    
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map<String, dynamic> && data['success'] == true) {
        return data['data'] as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        return data;
      }
    }
    throw Exception('Failed to fetch daily training plan: ${res.statusMessage}');
  }

  /// Submit daily training completion
  Future<Map<String, dynamic>> submitCompletion({
    required int dailyPlanId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    final dio = await _authedDio();
    
    final payload = {
      'daily_plan_id': dailyPlanId,
      'completion_data': completionData,
    };
    
    print('🔍 Submitting daily training completion:');
    print('Endpoint: /api/dailyTraining/mobile/complete');
    print('Payload: $payload');
      // Do not print Authorization header
    
    try {
      final res = await dio.post('/api/dailyTraining/mobile/complete', data: payload);
      print('🔍 Daily Training Completion API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data;
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to submit daily training completion: ${res.statusMessage}');
    } catch (e) {
      print('❌ Daily Training Completion Error Details:');
      print('Error: $e');
      if (e is DioException) {
        print('Status Code: ${e.response?.statusCode}');
        print('Response Data: ${e.response?.data}');
        print('Request Data: ${e.requestOptions.data}');
        final redactedHeaders = Map<String, dynamic>.from(e.requestOptions.headers);
        if (redactedHeaders.containsKey('Authorization')) {
          redactedHeaders['Authorization'] = 'REDACTED';
        }
        print('Request Headers: $redactedHeaders');
        
        // Handle specific error cases
        if (e.response?.statusCode == 403) {
          print('🚫 403 Forbidden: User does not have permission to access daily training endpoints');
          print('💡 This is likely a backend permissions issue. Data will be stored locally.');
        } else if (e.response?.statusCode == 401) {
          print('🔐 401 Unauthorized: Token may be expired or invalid');
        }
      }
      rethrow;
    }
  }

  /// Get training statistics
  Future<Map<String, dynamic>> getTrainingStats({int? userId}) async {
    try {
      final dio = await _authedDio();
      final res = await dio.get('/api/dailyTraining/mobile/stats', queryParameters: {
        if (userId != null) 'user_id': userId,
      });
      print('🔍 Training Stats API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to fetch training statistics: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to access training stats');
        print('💡 This is likely a backend permissions issue. Using local data only.');
      }
      rethrow;
    }
  }

  /// Get today's training plans
  Future<List<Map<String, dynamic>>> getTodaysPlans() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    return await getDailyPlans(date: today);
  }

  /// Create completion data for a single exercise
  static Map<String, dynamic> createCompletionItem({
    required int itemId,
    required int setsCompleted,
    required int repsCompleted,
    required double weightUsed,
    required int minutesSpent,
    String? notes,
  }) {
    return {
      'item_id': itemId,
      'sets_completed': setsCompleted,
      'reps_completed': repsCompleted,
      'weight_used': weightUsed,
      'minutes_spent': minutesSpent,
      if (notes != null) 'notes': notes,
    };
  }

  /// Store daily training plan data when a plan is started
  // Get daily training plans for mobile
  Future<List<Map<String, dynamic>>> getDailyTrainingPlans({int? userId}) async {
    try {
      final dio = await _authedDio();
      
      final res = await dio.get('/api/dailyTraining/mobile/plans', queryParameters: {
        if (userId != null) 'user_id': userId,
      });
      
      print('🔍 DailyTrainingService - Get daily plans response status: ${res.statusCode}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      print('❌ DailyTrainingService - Error getting daily training plans: $e');
      return [];
    }
  }

  // Get specific daily training plan
  Future<Map<String, dynamic>> getDailyTrainingPlan(int planId) async {
    try {
      final dio = await _authedDio();
      
      final res = await dio.get('/api/dailyTraining/mobile/plans/$planId');
      
      print('🔍 DailyTrainingService - Get daily plan $planId response status: ${res.statusCode}');
      
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(res.data);
      }
      return {};
    } catch (e) {
      print('❌ DailyTrainingService - Error getting daily training plan $planId: $e');
      return {};
    }
  }

  // Submit daily training completion
  Future<Map<String, dynamic>> submitDailyTrainingCompletion({
    required int planId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    try {
      final dio = await _authedDio();
      
      // Transform any lightweight completion entries into the expected schema
      final List<Map<String, dynamic>> normalizedItems = completionData.map((e) {
        final int itemId = int.tryParse((e['item_id'] ?? '0').toString()) ?? 0;
        final int sets = int.tryParse((e['sets_completed'] ?? e['sets'] ?? '0').toString()) ?? 0;
        final int reps = int.tryParse((e['reps_completed'] ?? e['reps'] ?? '0').toString()) ?? 0;
        final double weight = double.tryParse((e['weight_used'] ?? e['weight'] ?? '0').toString()) ?? 0.0;
        final int minutes = int.tryParse((e['minutes_spent'] ?? e['minutes'] ?? '0').toString()) ?? 0;
        final dynamic day = e['day'];
        final String workoutName = (e['workout_name'] ?? e['name'] ?? '').toString();
        final String? notes = e['notes']?.toString();
        final String composedNotes = [
          if (notes != null && notes.isNotEmpty) notes,
          if (workoutName.isNotEmpty) 'Workout: $workoutName',
          if (day != null) 'Day: ${int.tryParse(day.toString()) != null ? (int.parse(day.toString()) + 1) : day}',
          'Source: Plans tab'
        ].where((s) => s.isNotEmpty).join(' | ');
        return {
          'item_id': itemId,
          'sets_completed': sets,
          'reps_completed': reps,
          'weight_used': weight,
          'minutes_spent': minutes,
          if (composedNotes.isNotEmpty) 'notes': composedNotes,
        };
      }).toList();
      
      final payload = {
        // Backend expects daily_plan_id here
        'daily_plan_id': planId,
        'completion_data': normalizedItems,
        'completed_at': DateTime.now().toIso8601String(),
      };
      
      final res = await dio.post('/api/dailyTraining/mobile/complete', data: payload);
      
      print('🔍 DailyTrainingService - Submit completion response status: ${res.statusCode}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data);
      }
      throw Exception('Failed to submit daily training completion: ${res.statusMessage}');
    } catch (e) {
      print('❌ DailyTrainingService - Error submitting daily training completion: $e');
      rethrow;
    }
  }


  Future<Map<String, dynamic>> storeDailyTrainingPlan({
    required int planId,
    required String planType, // 'manual' or 'ai_generated'
    required List<Map<String, dynamic>> dailyPlans,
    required int userId,
    String? planCategory,
    String? userLevel,
  }) async {
    try {
      final dio = await _authedDio();

      // Normalize daily plans to backend schema
      List<Map<String, dynamic>> normalizedDays = [];
      final DateTime baseDate = DateTime.now();
      for (int i = 0; i < dailyPlans.length; i++) {
        final day = dailyPlans[i];
        final List rawWorkouts = (day['workouts'] ?? day['items'] ?? []) as List;
        final List<Map<String, dynamic>> exercises = [];
        int totalMinutes = 0;
        int totalSets = 0;
        int totalReps = 0;
        double totalWeight = 0.0;

        for (final w in rawWorkouts) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(w as Map);
          final String exerciseName = (m['name'] ?? m['workout_name'] ?? m['muscle_group'] ?? 'Workout').toString();
          final int sets = int.tryParse(m['sets']?.toString() ?? '0') ?? 0;
          final int reps = int.tryParse(m['reps']?.toString() ?? '0') ?? 0;
          final double weight = double.tryParse(m['weight_kg']?.toString() ?? m['weight']?.toString() ?? '0') ?? 0.0;
          final int minutes = int.tryParse(m['minutes']?.toString() ?? m['training_minutes']?.toString() ?? '0') ?? 0;
          final int exerciseType = int.tryParse(m['exercise_types']?.toString() ?? m['exercise_type']?.toString() ?? '0') ?? 0;

          exercises.add({
            'exercise_name': exerciseName,
            'sets': sets,
            'reps': reps,
            'weight_kg': weight,
            'minutes': minutes,
            'exercise_type': exerciseType,
          });

          totalMinutes += minutes;
          totalSets += sets;
          totalReps += reps;
          totalWeight += weight;
        }

        final String dayName = (day['workout_name']?.toString()) ?? 'Day ${day['day'] ?? (i + 1)}';
        final String planDate = (day['date'] ?? day['plan_date'])?.toString() ?? baseDate.add(Duration(days: i)).toIso8601String().split('T').first;
        final String dayCategory = day['plan_category'] ?? day['exercise_plan_category'] ?? planCategory ?? 'Training Plan';
        final String dayUserLevel = day['user_level'] ?? userLevel ?? 'Beginner';
        
        normalizedDays.add({
          'plan_date': planDate,
          'workout_name': dayName,
          'plan_category': dayCategory,
          'user_level': dayUserLevel,
          'exercises_details': exercises,
          // Note: Server computes these totals from exercises_details
          // We include them for reference, but backend will recalculate
          'training_minutes': totalMinutes,
          'total_exercises': exercises.length,
          'total_sets': totalSets,
          'total_reps': totalReps,
          'total_weight_kg': totalWeight,
        });
      }

      final payload = {
        'plan_type': planType,
        'user_id': userId,
        'source_plan_id': planId,
        'daily_plans': normalizedDays,
        // Note: plan_category and user_level are now in each daily_plan entry
      };

      final res = await dio.post('/api/dailyTraining/mobile/plans/store', data: payload);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data is Map ? res.data : {'success': true, 'data': res.data});
      }
      throw Exception('Failed to store daily training plans: HTTP ${res.statusCode}');
    } catch (e) {
      print('❌ DailyTrainingService - Error storing daily training plan: $e');
      rethrow;
    }
  }
}
