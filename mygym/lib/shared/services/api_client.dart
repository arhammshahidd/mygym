import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

class ApiClient {
  final Dio _dio;

  ApiClient._internal(this._dio);

  factory ApiClient({String? baseUrl, String? authToken}) {
    String _defaultBase() {
      // Choose a sensible default per platform; Android emulator uses 10.0.2.2
      if (kIsWeb) return 'http://localhost:5000';
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return 'http://10.0.2.2:5000';
        default:
          return 'http://localhost:5000';
      }
    }
    String _computeBaseUrl() {
      // Start from explicit base or configured base
      String url = baseUrl ?? AppConfig.baseApiUrl;
      // On Android emulators, map localhost to 10.0.2.2
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        url = url.replaceFirst('localhost', '10.0.2.2');
      }
      return url.isEmpty ? _defaultBase() : url;
    }
    final dio = Dio(
      BaseOptions(
        baseUrl: _computeBaseUrl(),
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
