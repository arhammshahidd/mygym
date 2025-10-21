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
    print('Auth token present: ${dio.options.headers['Authorization'] != null}');
    
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
        print('Request Headers: ${e.requestOptions.headers}');
        
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
  Future<Map<String, dynamic>> getTrainingStats() async {
    try {
      final dio = await _authedDio();
      final res = await dio.get('/api/dailyTraining/mobile/stats');
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
}
