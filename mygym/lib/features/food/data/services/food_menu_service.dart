import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class FoodMenuService {
  final AuthService _auth = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  Future<List<Map<String, dynamic>>> listAssignments({int? userId}) async {
    final dio = await _authedDio();
    // Prefer mobile-focused endpoint when userId is provided
    final String path = (userId != null)
        ? '${AppConfig.foodMenuAssignmentsPath}/user/$userId'
        : AppConfig.foodMenuAssignmentsPath;
    final res = await dio.get(path, queryParameters: {
      // Keep query support for backward compatibility if backend accepts it
      if (userId == null) 'limit': 20,
    });
    if (res.statusCode == 200) {
      final data = res.data is Map<String, dynamic> ? (res.data['data'] ?? res.data) : res.data;
      final list = List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e)));
      return list;
    }
    throw Exception('Failed to fetch food assignments');
  }

  // Optional: details endpoint if available later
  Future<Map<String, dynamic>> getAssignment(int id) async {
    final dio = await _authedDio();
    final res = await dio.get('${AppConfig.foodMenuAssignmentsPath}/$id');
    if (res.statusCode == 200) {
      final data = res.data is Map<String, dynamic> ? res.data['data'] : res.data;
      return Map<String, dynamic>.from(data);
    }
    throw Exception('Failed to fetch assignment');
  }
}


