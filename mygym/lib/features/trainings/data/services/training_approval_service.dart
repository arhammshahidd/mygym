import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class TrainingApprovalService {
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> sendForApproval({
    required String source, // 'manual' | 'ai'
    required Map<String, dynamic> payload,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    final dio = ApiClient(authToken: token).dio;

    // Add gym_id to payload if not present (required by backend)
    final enhancedPayload = Map<String, dynamic>.from(payload);
    if (!enhancedPayload.containsKey('gym_id')) {
      // Try to get gym_id from user_id (assuming gym_id = 11 for now)
      // TODO: Get actual gym_id from user profile or JWT token
      enhancedPayload['gym_id'] = 11; // Default gym_id
      print('🔍 TrainingApprovalService - Added default gym_id: 11');
    }

    final body = {
      'source': source,
      'data': enhancedPayload,
    };
    
    // For AI plans, add required fields at root level if they exist in the payload
    if ((source == 'ai' || source == 'manual') && enhancedPayload.containsKey('start_date')) {
      body['start_date'] = enhancedPayload['start_date'];
      body['end_date'] = enhancedPayload['end_date'];
      
      // Add other potentially required fields
      if (enhancedPayload.containsKey('workout_name')) {
        body['workout_name'] = enhancedPayload['workout_name'];
      }
      if (enhancedPayload.containsKey('category')) {
        body['category'] = enhancedPayload['category'];
      }
      if (enhancedPayload.containsKey('plan_id')) {
        body['plan_id'] = enhancedPayload['plan_id'];
      }
      if (enhancedPayload.containsKey('user_id')) {
        body['user_id'] = enhancedPayload['user_id'];
      }
      if (enhancedPayload.containsKey('plan_type')) {
        body['plan_type'] = enhancedPayload['plan_type'];
      }
      if (enhancedPayload.containsKey('minutes')) body['minutes'] = enhancedPayload['minutes'];
      if (enhancedPayload.containsKey('total_exercises')) body['total_exercises'] = enhancedPayload['total_exercises'];
      if (enhancedPayload.containsKey('total_days')) body['total_days'] = enhancedPayload['total_days'];
      if (enhancedPayload.containsKey('user_level')) body['user_level'] = enhancedPayload['user_level'];
      if (enhancedPayload.containsKey('items')) body['items'] = enhancedPayload['items'];
      if (enhancedPayload.containsKey('exercises_details')) body['exercises_details'] = enhancedPayload['exercises_details'];
      
    print('🔍 TrainingApprovalService - Added required fields to root level');
    }

    print('🔍 TrainingApprovalService - Enhanced Payload prepared');
    print('🔍 TrainingApprovalService - Endpoint: ${AppConfig.trainingApprovalsPath}');
    print('🔍 TrainingApprovalService - Base URL: ${dio.options.baseUrl}');
    
    // Try to decode JWT token to check roles
    try {
      // Intentionally skip decoding/printing JWT contents to avoid sensitive data leakage
      final parts = token.split('.');
      if (parts.length == 3) {
        print('🔍 TrainingApprovalService - JWT detected (not printing contents)');
      }
    } catch (e) {
      print('🔍 TrainingApprovalService - Could not decode JWT: $e');
    }

    try {
      final Response res = await dio.post(AppConfig.trainingApprovalsPath, data: body);
      print('🔍 TrainingApprovalService - Response status: ${res.statusCode}');
      print('🔍 TrainingApprovalService - Response data: ${res.data}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data);
      }
      throw Exception('Failed to send plan for approval: ${res.statusMessage}');
    } on DioException catch (e) {
      print('❌ TrainingApprovalService - DioException occurred:');
      print('❌   - Status Code: ${e.response?.statusCode}');
      print('❌   - Response Data: ${e.response?.data}');
      print('❌   - Response Headers: ${e.response?.headers}');
      print('❌   - Request Data: ${e.requestOptions.data}');
      // Redact sensitive headers
      final redactedHeaders = Map<String, dynamic>.from(e.requestOptions.headers);
      if (redactedHeaders.containsKey('Authorization')) {
        redactedHeaders['Authorization'] = 'REDACTED';
      }
      print('❌   - Request Headers: $redactedHeaders');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendPlanForApproval(Map<String, dynamic> payload) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    final dio = ApiClient(authToken: token).dio;

    print('🔍 TrainingApprovalService - Sending plan for approval');
    print('🔍 TrainingApprovalService - Payload: $payload');
    print('🔍 TrainingApprovalService - Base URL: ${dio.options.baseUrl}');
    print('🔍 TrainingApprovalService - Using endpoint: /api/training-approvals');
    
    final Response res = await dio.post('/api/training-approvals', data: payload);
    print('🔍 TrainingApprovalService - Response status: ${res.statusCode}');
    print('🔍 TrainingApprovalService - Response data: ${res.data}');
    
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to send plan for approval: ${res.statusMessage}');
  }

  // REST: GET /api/trainingApprovals/:id → { approval_status: 'APPROVED' | 'PENDING' | ... }
  Future<Map<String, dynamic>> getApproval(int id) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    final dio = ApiClient(authToken: token).dio;

    final Response res = await dio.get('/api/trainingApprovals/$id');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map<String, dynamic>) {
        // Common wrappers: { success, data } or raw object
        if (data['data'] is Map<String, dynamic>) {
          return Map<String, dynamic>.from(data['data'] as Map);
        }
        return Map<String, dynamic>.from(data);
      }
      throw Exception('Unexpected approval response type: ${data.runtimeType}');
    }
    throw Exception('Failed to fetch approval: HTTP ${res.statusCode}');
  }
}


