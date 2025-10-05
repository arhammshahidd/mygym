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

    final body = {
      'source': source,
      'data': payload,
    };

    print('🔍 TrainingApprovalService - sendForApproval called');
    print('🔍 TrainingApprovalService - Source: $source');
    print('🔍 TrainingApprovalService - Payload: $payload');
    print('🔍 TrainingApprovalService - Body: $body');
    print('🔍 TrainingApprovalService - Endpoint: ${AppConfig.trainingApprovalsPath}');

    final Response res = await dio.post(AppConfig.trainingApprovalsPath, data: body);
    print('🔍 TrainingApprovalService - Response status: ${res.statusCode}');
    print('🔍 TrainingApprovalService - Response data: ${res.data}');
    
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to send plan for approval: ${res.statusMessage}');
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


