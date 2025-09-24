import 'package:dio/dio.dart';
import '../../../../shared/services/api_client.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../../shared/services/openai_service.dart';

class AiTrainingService {
  final AuthService _authService = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  // Requests
  Future<List<dynamic>> listRequests({int? userId}) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appAIPlans/requests', queryParameters: {
      if (userId != null) 'user_id': userId,
    });
    if (res.statusCode == 200) return List<dynamic>.from(res.data);
    throw Exception('Failed to fetch AI requests');
  }

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    final res = await dio.post('/api/appAIPlans/requests', data: payload);
    if (res.statusCode == 200 || res.statusCode == 201) return Map<String, dynamic>.from(res.data);
    throw Exception('Failed to create AI request');
  }

  // Generated
  Future<List<dynamic>> listGenerated({int? userId}) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appAIPlans/generated', queryParameters: {
      if (userId != null) 'user_id': userId,
    });
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return List<dynamic>.from(data.map((e) => _normalizeGenerated(e)));
      }
      if (data is Map<String, dynamic>) {
        if (data['data'] is List) return List<dynamic>.from((data['data'] as List).map((e) => _normalizeGenerated(e)));
        if (data['items'] is List) return List<dynamic>.from((data['items'] as List).map((e) => _normalizeGenerated(e)));
        if (data['result'] is List) return List<dynamic>.from((data['result'] as List).map((e) => _normalizeGenerated(e)));
      }
      return [];
    }
    throw Exception('Failed to fetch AI generated plans');
  }

  Future<Map<String, dynamic>> getGenerated(int id) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appAIPlans/generated/$id');
    if (res.statusCode == 200) return _normalizeGenerated(res.data);
    throw Exception('Failed to fetch AI generated plan');
  }

  Future<Map<String, dynamic>> createGenerated(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    try {
      // If no items provided, generate via OpenAI first to create a full plan
      Map<String, dynamic> toSend = payload;
      final items = (payload['items'] is List) ? payload['items'] as List : const [];
      if (items.isEmpty) {
        if (AppConfig.openAIApiKey.isEmpty) {
          // Build minimal acceptable payload without calling external APIs
          final plan = payload;
          final exPlan = plan['exercise_plan']?.toString() ?? plan['exercise_plan_category']?.toString() ?? 'Strength';
          toSend = {
            'user_id': plan['user_id'] ?? 0,
            'start_date': plan['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
            'end_date': plan['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T').first,
            'exercise_plan': exPlan,
            'total_workouts': 1,
            'total_training_minutes': 20,
            'items': [
              {
                'name': '$exPlan Workout',
                'sets': 3,
                'reps': 10,
                'weight': 0,
                'training_minutes': 20,
                'exercise_types': 'general',
              }
            ],
          };
        } else {
          final gen = await OpenAIService().generatePlanJson(
            userId: payload['user_id'] ?? 0,
            exercisePlan: payload['exercise_plan']?.toString() ?? payload['exercise_plan_category']?.toString() ?? 'Strength',
            startDate: payload['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
            endDate: payload['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T').first,
            age: payload['age'] ?? 25,
            heightCm: payload['height_cm'] ?? 170,
            weightKg: payload['weight_kg'] ?? 70,
            gender: payload['gender']?.toString() ?? 'Male',
            futureGoal: payload['future_goal']?.toString() ?? payload['goal']?.toString() ?? 'build muscle',
          );
          toSend = gen;
        }
      }
      final res = await dio.post('/api/appAIPlans/generated', data: _mapToBackendGenerated(toSend));
      if (res.statusCode == 200 || res.statusCode == 201) return Map<String, dynamic>.from(res.data);
      throw Exception('Failed to create AI generated plan');
    } on DioException catch (_) {
      // Fallback: generate using OpenAI then save to backend
      final gen = await OpenAIService().generatePlanJson(
        userId: payload['user_id'] ?? 0,
        exercisePlan: payload['exercise_plan']?.toString() ?? payload['exercise_plan_category']?.toString() ?? 'Strength',
        startDate: payload['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
        endDate: payload['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T').first,
        age: payload['age'] ?? 25,
        heightCm: payload['height_cm'] ?? 170,
        weightKg: payload['weight_kg'] ?? 70,
        gender: payload['gender']?.toString() ?? 'Male',
        futureGoal: payload['future_goal']?.toString() ?? payload['goal']?.toString() ?? 'build muscle',
      );
      final res2 = await dio.post('/api/appAIPlans/generated', data: _mapToBackendGenerated(gen));
      if (res2.statusCode == 200 || res2.statusCode == 201) return Map<String, dynamic>.from(res2.data);
      throw Exception('Failed to create AI generated plan after OpenAI');
    }
  }

  Map<String, dynamic> _normalizeGenerated(dynamic raw) {
    final map = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : Map<String, dynamic>.from(raw as Map);
    // unify keys for UI
    map['exercise_plan_category'] = map['exercise_plan_category'] ?? map['exercise_plan'] ?? map['category'];
    map['training_minutes'] = map['training_minutes'] ?? map['total_training_minutes'];
    if (map['items'] is List) {
      map['items'] = (map['items'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['workout_name'] = m['workout_name'] ?? m['name'];
        m['minutes'] = m['minutes'] ?? m['training_minutes'];
        m['weight_kg'] = m['weight_kg'] ?? m['weight'];
        return m;
      }).toList();
    }
    return map;
  }

  Map<String, dynamic> _mapToBackendGenerated(Map<String, dynamic> input) {
    final List items = (input['items'] is List) ? List.from(input['items']) : <dynamic>[];
    final mappedItems = items.map((e) {
      final m = e as Map;
      final minutes = int.tryParse(m['training_minutes']?.toString() ?? m['minutes']?.toString() ?? '0') ?? 0;
      final sets = int.tryParse(m['sets']?.toString() ?? '0') ?? 0;
      final reps = int.tryParse(m['reps']?.toString() ?? '0') ?? 0;
      final weightKg = double.tryParse(m['weight']?.toString() ?? m['weight_kg']?.toString() ?? '0') ?? 0.0;
      return {
        'workout_name': (m['name'] ?? m['workout_name'] ?? 'Exercise').toString(),
        'exercise_types': (m['exercise_types'] ?? '').toString(),
        'sets': sets,
        'reps': reps,
        'weight_kg': weightKg,
        'minutes': minutes,
      };
    }).toList();

    final totalMinutes = mappedItems.fold<int>(0, (s, it) => s + (it['minutes'] as int));
    final totalWorkouts = mappedItems.length;

    return {
      if (input['request_id'] != null) 'request_id': input['request_id'],
      'user_id': input['user_id'],
      'start_date': input['start_date']?.toString(),
      'end_date': input['end_date']?.toString(),
      'exercise_plan_category': input['exercise_plan_category']?.toString() ?? input['exercise_plan']?.toString() ?? 'Strength',
      'total_workouts': input['total_workouts'] ?? totalWorkouts,
      'training_minutes': input['training_minutes'] ?? input['total_training_minutes'] ?? totalMinutes,
      'items': mappedItems,
    };
  }

  Future<Map<String, dynamic>> updateGenerated(int id, Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    final res = await dio.put('/api/appAIPlans/generated/$id', data: payload);
    if (res.statusCode == 200) return Map<String, dynamic>.from(res.data);
    throw Exception('Failed to update AI generated plan');
  }

  Future<void> deleteGenerated(int id) async {
    final dio = await _authedDio();
    final res = await dio.delete('/api/appAIPlans/generated/$id');
    if (res.statusCode != 200) throw Exception('Failed to delete AI generated plan');
  }
}


