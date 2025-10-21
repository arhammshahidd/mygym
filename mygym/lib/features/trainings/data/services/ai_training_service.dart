import 'package:dio/dio.dart';
import '../../../../shared/services/api_client.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../../shared/services/gemini_service.dart';

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
    print('🤖 AI Training Service - Fetching AI generated plans...');
    print('🤖 User ID: $userId');
    print('🤖 Endpoint: /api/appAIPlans/generated');
    
    final res = await dio.get('/api/appAIPlans/generated', queryParameters: {
      if (userId != null) 'user_id': userId,
    });
    
    print('🤖 AI Training Service - Response status: ${res.statusCode}');
    print('🤖 AI Training Service - Response data: ${res.data}');
    print('🤖 AI Training Service - Response data type: ${res.data.runtimeType}');
    
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        print('🤖 AI Training Service - Data is List with ${data.length} items');
        if (data.isEmpty) {
          print('🤖 AI Training Service - List is empty, returning empty list');
          return [];
        }
        print('🤖 AI Training Service - First item: ${data.first}');
        return List<dynamic>.from(data.map((e) => _normalizeGenerated(e)));
      }
      if (data is Map<String, dynamic>) {
        print('🤖 AI Training Service - Data is Map with keys: ${data.keys.toList()}');
        if (data['data'] is List) {
          final list = data['data'] as List;
          print('🤖 AI Training Service - Found data.data with ${list.length} items');
          return List<dynamic>.from(list.map((e) => _normalizeGenerated(e)));
        }
        if (data['items'] is List) {
          final list = data['items'] as List;
          print('🤖 AI Training Service - Found data.items with ${list.length} items');
          return List<dynamic>.from(list.map((e) => _normalizeGenerated(e)));
        }
        if (data['result'] is List) {
          final list = data['result'] as List;
          print('🤖 AI Training Service - Found data.result with ${list.length} items');
          return List<dynamic>.from(list.map((e) => _normalizeGenerated(e)));
        }
        print('🤖 AI Training Service - No list found in Map, returning empty list');
        return [];
      }
      print('🤖 AI Training Service - Data is neither List nor Map, returning empty list');
      return [];
    }
    print('🤖 AI Training Service - Non-200 status code: ${res.statusCode}');
    throw Exception('Failed to fetch AI generated plans');
  }

  Future<Map<String, dynamic>> getGenerated(int id) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appAIPlans/generated/$id');
    if (res.statusCode == 200) {
      final planData = _normalizeGenerated(res.data);
      
      // If the plan doesn't have items, try to fetch them separately
      if (planData['items'] == null || (planData['items'] as List).isEmpty) {
        print('🔍 AI Training Service - Plan has no items, trying to fetch items separately...');
        try {
          final itemsRes = await dio.get('/api/appAIPlans/generated/$id/items');
          if (itemsRes.statusCode == 200) {
            final itemsData = itemsRes.data;
            List<Map<String, dynamic>> items = [];
            
            if (itemsData is List) {
              items = List<Map<String, dynamic>>.from(itemsData);
            } else if (itemsData is Map && itemsData['data'] is List) {
              items = List<Map<String, dynamic>>.from(itemsData['data']);
            } else if (itemsData is Map && itemsData['items'] is List) {
              items = List<Map<String, dynamic>>.from(itemsData['items']);
            }
            
            if (items.isNotEmpty) {
              print('🔍 AI Training Service - Fetched ${items.length} items separately');
              planData['items'] = items;
            }
          }
        } catch (e) {
          print('⚠️ AI Training Service - Failed to fetch items separately: $e');
        }
      }
      
      return planData;
    }
    throw Exception('Failed to fetch AI generated plan');
  }

  Future<Map<String, dynamic>> createGenerated(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    try {
      print('🤖 createGenerated called with payload: $payload');
      // If no items provided, generate via Gemini first to create a full plan (only if frontend has API key)
      Map<String, dynamic> toSend = payload;
      final items = (payload['items'] is List) ? payload['items'] as List : const [];
      print('🤖 Items in payload: ${items.length}');
      if (items.isEmpty) {
        // Check if frontend has Gemini API key
        print('🤖 Checking frontend Gemini API key...');
        print('🤖 AppConfig.geminiApiKey.isNotEmpty: ${AppConfig.geminiApiKey.isNotEmpty}');
        print('🤖 AppConfig.geminiApiKey length: ${AppConfig.geminiApiKey.length}');
        if (AppConfig.geminiApiKey.isNotEmpty) {
          print('🤖 Frontend has Gemini key, generating client-side...');
          // Use Gemini as the AI generator
          final gen = await GeminiService().generatePlanJson(
            userId: payload['user_id'] ?? 0,
            exercisePlan: payload['exercise_plan']?.toString() ?? payload['exercise_plan_category']?.toString() ?? 'Strength',
            startDate: payload['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
            endDate: payload['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T').first,
            age: payload['age'] ?? 25,
            heightCm: payload['height_cm'] ?? 170,
            weightKg: payload['weight_kg'] ?? 70,
            gender: payload['gender']?.toString() ?? 'Male',
            futureGoal: payload['future_goal']?.toString() ?? payload['goal']?.toString() ?? 'build muscle',
            userLevel: payload['user_level']?.toString(),
          );
          toSend = gen;
        } else {
          print('🤖 Frontend has no Gemini key, sending to backend for generation...');
          // Frontend doesn't have Gemini key, let backend handle generation
          // Just send the payload as-is, backend will generate items via Gemini
        }
      }
      final res = await dio.post('/api/appAIPlans/generated', data: _mapToBackendGenerated(toSend));
      if (res.statusCode == 200 || res.statusCode == 201) return Map<String, dynamic>.from(res.data);
      throw Exception('Failed to create AI generated plan');
    } on DioException catch (_) {
      // Fallback: if frontend has Gemini key, try client-side generation
      if (AppConfig.geminiApiKey.isNotEmpty) {
        print('🤖 Fallback: Using client-side Gemini generation...');
        final gen = await GeminiService().generatePlanJson(
          userId: payload['user_id'] ?? 0,
          exercisePlan: payload['exercise_plan']?.toString() ?? payload['exercise_plan_category']?.toString() ?? 'Strength',
          startDate: payload['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first,
          endDate: payload['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T').first,
          age: payload['age'] ?? 25,
          heightCm: payload['height_cm'] ?? 170,
          weightKg: payload['weight_kg'] ?? 70,
          gender: payload['gender']?.toString() ?? 'Male',
          futureGoal: payload['future_goal']?.toString() ?? payload['goal']?.toString() ?? 'build muscle',
          userLevel: payload['user_level']?.toString(),
        );
        final res2 = await dio.post('/api/appAIPlans/generated', data: _mapToBackendGenerated(gen));
        if (res2.statusCode == 200 || res2.statusCode == 201) return Map<String, dynamic>.from(res2.data);
        throw Exception('Failed to create AI generated plan after Gemini fallback');
      } else {
        print('🤖 Fallback: No frontend Gemini key, throwing original error...');
        throw Exception('Failed to create AI generated plan - no frontend Gemini key available');
      }
    }
  }

  /// Create AI plan directly via backend at /api/appAIPlans/generated (server-side generation)
  Future<Map<String, dynamic>> createGeneratedViaBackend(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    
    print('🤖 Backend generation: Sending payload to backend for AI generation...');
    print('🤖 Backend generation: Payload: $payload');
    print('🤖 Backend generation: Payload keys: ${payload.keys.toList()}');
    print('🤖 Backend generation: Items in payload: ${payload['items']}');
    print('🤖 Backend generation: Exercise plan category: ${payload['exercise_plan_category']}');
    print('🤖 Backend generation: User level: ${payload['user_level']}');
    print('🤖 Backend generation: Future goal: ${payload['future_goal']}');
    
    // Send the payload directly to backend - let backend handle Gemini API calls
    // Use the generate endpoint which creates the plan with items
    final res = await dio.post('/api/appAIPlans/generate', data: payload);
    print('🤖 Backend generation: Response status: ${res.statusCode}');
    print('🤖 Backend generation: Response data: ${res.data}');
    
    if (res.statusCode == 200 || res.statusCode == 201) {
      print('✅ Backend generation: Successfully created plan via backend');
      final responseData = Map<String, dynamic>.from(res.data);
      
      // Check if the response contains items
      if (responseData.containsKey('data') && responseData['data'] is Map) {
        final planData = responseData['data'] as Map<String, dynamic>;
        final items = planData['items'] as List?;
        print('🤖 Backend generation: Plan created with ${items?.length ?? 0} items');
        if (items != null && items.isNotEmpty) {
          print('🤖 Backend generation: Sample item: ${items.first}');
        } else {
          print('⚠️ Backend generation: No items generated by backend!');
        }
      }
      
      return responseData;
    }
    throw Exception('Failed to create AI plan via backend: ${res.statusCode} ${res.statusMessage}');
  }

  Map<String, dynamic> _normalizeGenerated(dynamic raw) {
    final map = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : Map<String, dynamic>.from(raw as Map);
    
    // Handle nested data structure (if response has 'data' wrapper)
    Map<String, dynamic> actualData = map;
    if (map.containsKey('data') && map['data'] is Map) {
      actualData = Map<String, dynamic>.from(map['data']);
    }
    
    // unify keys for UI
    actualData['exercise_plan_category'] = actualData['exercise_plan_category'] ?? actualData['exercise_plan'] ?? actualData['category'];
    actualData['training_minutes'] = actualData['training_minutes'] ?? actualData['total_training_minutes'];
    
    // Handle items array
    if (actualData['items'] is List) {
      actualData['items'] = (actualData['items'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        // Use only AI-generated workout names, no hardcoded fallbacks
        final rawName = (m['workout_name'] ?? m['name'] ?? '').toString().trim();
        m['workout_name'] = rawName.isEmpty ? 'AI Generated Workout' : rawName;
        m['minutes'] = m['minutes'] ?? m['training_minutes'];
        m['weight_kg'] = m['weight_kg'] ?? m['weight'];
        // Ensure exercise_types is numeric count (for GIF selection)
        final types = m['exercise_types'];
        if (types is String) {
          final parsed = int.tryParse(types);
          if (parsed != null) m['exercise_types'] = parsed;
        }
        return m;
      }).toList();
    } else {
      // If no items array, initialize as empty
      actualData['items'] = <Map<String, dynamic>>[];
    }
    
    return actualData;
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


