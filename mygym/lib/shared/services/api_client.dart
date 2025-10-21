import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../features/auth/data/services/auth_service.dart';

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

    // Add interceptor to handle 401 and 403 errors globally (non-disruptive)
    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          print('🔐 401 Unauthorized received - validating token before logout');
          try {
            final authService = AuthService();
            final stillValid = await authService.validateTokenWithBackend();
            if (!stillValid) {
              // Only then logout
              await authService.handleSessionExpiration();
              // Avoid named routes; leave navigation to controllers/flows
            } else {
              print('🔐 Token validated as still valid after 401 - ignoring');
            }
          } catch (e) {
            // Network or other transient errors - don't logout to avoid accidental sign-outs
            print('🔐 Token revalidation failed after 401 (non-fatal): $e');
          }
        } else if (error.response?.statusCode == 403) {
          print('🔐 403 Forbidden received - checking token validity');
          try {
            final authService = AuthService();
            final stillValid = await authService.validateTokenWithBackend();
            if (!stillValid) {
              // Token is invalid, logout
              await authService.handleSessionExpiration();
            } else {
              // Token is valid but access denied - this might be a permissions issue
              print('🔐 Token valid but access denied - possible permissions issue');
            }
          } catch (e) {
            print('🔐 Token validation failed after 403 (non-fatal): $e');
          }
        }
        handler.next(error);
      },
    ));

    return ApiClient._internal(dio);
  }

  Dio get dio => _dio;
}
