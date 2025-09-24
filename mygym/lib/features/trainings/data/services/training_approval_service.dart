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

    final Response res = await dio.post(AppConfig.trainingApprovalsPath, data: body);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to send plan for approval');
  }
}


