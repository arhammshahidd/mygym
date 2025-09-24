import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class ManualTrainingService {
  final AuthService _authService = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  Future<List<dynamic>> listPlans({int? userId}) async {
    final dio = await _authedDio();
    // Backend returns plans for the authenticated user; no params needed
    final res = await dio.get('/api/appManualTraining/');
    print('🔍 Manual Training API Response:');
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
    print('Data type: ${res.data.runtimeType}');
    
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        print('✅ Returning list with ${data.length} items');
        if (data.isNotEmpty) {
          print('📋 First item keys: ${(data.first as Map).keys}');
          print('📋 First item total_exercises: ${(data.first as Map)['total_exercises']}');
        }
        return List<dynamic>.from(data);
      }
      if (data is Map<String, dynamic>) {
        print('📦 Data is Map, checking keys: ${data.keys}');
        if (data['data'] is List) {
          print('✅ Found data.data with ${(data['data'] as List).length} items');
          return List<dynamic>.from(data['data']);
        }
        if (data['plans'] is List) {
          print('✅ Found data.plans with ${(data['plans'] as List).length} items');
          return List<dynamic>.from(data['plans']);
        }
        if (data['items'] is List) {
          print('✅ Found data.items with ${(data['items'] as List).length} items');
          return List<dynamic>.from(data['items']);
        }
        if (data['result'] is List) {
          print('✅ Found data.result with ${(data['result'] as List).length} items');
          return List<dynamic>.from(data['result']);
        }
        print('❌ No list found in map data');
      }
      print('❌ Returning empty list - data type not handled');
      return [];
    }
    throw Exception('Failed to fetch manual plans');
  }

  Future<Map<String, dynamic>> getPlan(int id) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/appManualTraining/$id');
    if (res.statusCode == 200) {
      final raw = res.data;
      print('🔍 Get Plan API Response for ID $id:');
      print('Raw data: $raw');
      print('Raw data type: ${raw.runtimeType}');
      
      Map<String, dynamic> plan;
      if (raw is Map<String, dynamic>) {
        // Common wrappers: { data: {...} } or { plan: {...} }
        if (raw['data'] is Map<String, dynamic>) {
          plan = Map<String, dynamic>.from(raw['data'] as Map);
        } else if (raw['plan'] is Map<String, dynamic>) {
          plan = Map<String, dynamic>.from(raw['plan'] as Map);
        } else {
          plan = Map<String, dynamic>.from(raw);
        }

        print('📋 Plan data keys: ${plan.keys}');
        print('📋 total_exercises value: ${plan['total_exercises']}');
        print('📋 total_workouts value: ${plan['total_workouts']}');
        print('📋 training_minutes value: ${plan['training_minutes']}');

        // Normalize items list under 'items'
        List<dynamic>? items;
        if (plan['items'] is List) {
          items = plan['items'] as List;
        } else if (plan['plan_items'] is List) {
          items = plan['plan_items'] as List;
        } else if (plan['workouts'] is List) {
          items = plan['workouts'] as List;
        } else if (raw['items'] is List) {
          items = raw['items'] as List;
        } else if (raw['data'] is Map<String, dynamic> && (raw['data']['items'] is List)) {
          items = raw['data']['items'] as List;
        }
        if (items != null) {
          plan['items'] = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          plan['items'] = <Map<String, dynamic>>[];
        }
        return plan;
      }
    }
    throw Exception('Failed to fetch plan');
  }

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    
    print('🔍 Service - createPlan called');
    print('🔍 Service - Payload being sent: $payload');
    print('🔍 Service - total_exercises in payload: ${payload['total_exercises']}');
    
    try {
      final res = await dio.post('/api/appManualTraining', data: payload);
      
      print('🔍 Service - Create response status: ${res.statusCode}');
      print('🔍 Service - Create response data: ${res.data}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        final responseData = Map<String, dynamic>.from(res.data);
        print('🔍 Service - total_exercises in response: ${responseData['total_exercises']}');
        return responseData;
      }
      throw Exception('Failed to create plan: ${res.statusMessage ?? res.statusCode}');
    } on DioException catch (e) {
      String msg = 'Failed to create plan';
      if (e.response?.data is Map<String, dynamic>) {
        final m = e.response!.data as Map<String, dynamic>;
        msg = m['message']?.toString() ?? m['error']?.toString() ?? msg;
      } else if (e.response?.data is String) {
        msg = e.response!.data as String;
      } else if (e.message != null) {
        msg = e.message!;
      }
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> updatePlan(int id, Map<String, dynamic> payload) async {
    final dio = await _authedDio();
    
    print('🔍 Service - updatePlan called with ID: $id');
    print('🔍 Service - Payload being sent: $payload');
    print('🔍 Service - total_exercises in payload: ${payload['total_exercises']}');
    
    final res = await dio.put('/api/appManualTraining/$id', data: payload);
    
    print('🔍 Service - Update response status: ${res.statusCode}');
    print('🔍 Service - Update response data: ${res.data}');
    
    if (res.statusCode == 200) {
      final responseData = Map<String, dynamic>.from(res.data);
      print('🔍 Service - total_exercises in response: ${responseData['total_exercises']}');
      return responseData;
    }
    throw Exception('Failed to update plan');
  }

  Future<void> deletePlan(int id) async {
    final dio = await _authedDio();
    try {
      print('🗑️ Sending delete request for plan ID: $id');
      final res = await dio.delete('/api/appManualTraining/$id');
      print('🗑️ Delete response status: ${res.statusCode}');
      print('🗑️ Delete response data: ${res.data}');
      
      if (res.statusCode == 200 || res.statusCode == 204) {
        print('✅ Plan deleted successfully from database');
        return;
      }
      throw Exception('Failed to delete plan: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      print('❌ DioException during delete: ${e.message}');
      print('❌ Response data: ${e.response?.data}');
      String msg = 'Failed to delete plan';
      if (e.response?.data is Map<String, dynamic>) {
        final m = e.response!.data as Map<String, dynamic>;
        msg = m['message']?.toString() ?? m['error']?.toString() ?? msg;
      } else if (e.response?.data is String) {
        msg = e.response!.data as String;
      } else if (e.message != null) {
        msg = e.message!;
      }
      throw Exception(msg);
    }
  }
}


