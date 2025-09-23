import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class ApiClient {
  final Dio _dio;

  ApiClient._internal(this._dio);

  factory ApiClient({String? baseUrl, String? authToken}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConfig.baseApiUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    if (authToken != null && authToken.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $authToken';
    }

    return ApiClient._internal(dio);
  }

  Dio get dio => _dio;
}
