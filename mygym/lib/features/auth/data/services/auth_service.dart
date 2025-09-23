import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';

class AuthService {
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.authToken);
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.authToken);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.authToken, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageKeys.authToken);
  }

  Future<String> login({required String phone, required String password}) async {
    final client = ApiClient();
    try {
      // Debug: Print the request details
      print('🔐 Login attempt:');
      print('📱 Phone: $phone');
      print('🔑 Password: ${password.replaceRange(2, password.length, '*' * (password.length - 2))}');
      print('🌐 URL: ${AppConfig.baseApiUrl}${AppConfig.loginPath}');
      
      final Response response = await client.dio.post(
        AppConfig.loginPath,
        data: {
          'phone': phone,
          'password': password,
        },
      );
      
      print('✅ Response Status: ${response.statusCode}');
      print('📄 Response Data: ${response.data}');

      // Handle different possible response formats
      final data = response.data as Map<String, dynamic>;
      
      // Try different possible token field names
      String? token = data['token']?.toString() ?? 
                     data['accessToken']?.toString() ?? 
                     data['access_token']?.toString() ??
                     data['authToken']?.toString();
      
      if (token == null || token.isEmpty) {
        throw Exception('No authentication token received from server');
      }
      
      await saveToken(token);
      return token;
    } on DioException catch (e) {
      // Debug: Print detailed error information
      print('❌ Login failed with DioException:');
      print('📊 Status Code: ${e.response?.statusCode}');
      print('📄 Response Data: ${e.response?.data}');
      print('🔗 Request URL: ${e.requestOptions.uri}');
      print('📝 Request Data: ${e.requestOptions.data}');
      
      String message = 'Login failed';
      
      if (e.response?.statusCode == 401) {
        // Check if it's an inactive user issue
        if (e.response?.data is Map<String, dynamic>) {
          final errorData = e.response!.data as Map<String, dynamic>;
          final errorMessage = errorData['message']?.toString().toLowerCase() ?? '';
          
          if (errorMessage.contains('inactive') || errorMessage.contains('disabled')) {
            message = 'Your account is inactive. Please contact support to activate your account.';
          } else if (errorMessage.contains('invalid credentials')) {
            message = 'Invalid phone number or password. Please check your credentials.';
          } else {
            message = errorMessage.isNotEmpty ? errorMessage : 'Invalid phone number or password. Please check your credentials.';
          }
        } else {
          message = 'Invalid phone number or password. Please check your credentials.';
        }
      } else if (e.response?.statusCode == 404) {
        message = 'Login endpoint not found. Please check if the backend is running.';
      } else if (e.response?.statusCode == 500) {
        message = 'Server error. Please try again later.';
      } else if (e.response?.data is Map<String, dynamic>) {
        final errorData = e.response!.data as Map<String, dynamic>;
        message = errorData['message']?.toString() ?? 
                 errorData['error']?.toString() ?? 
                 errorData['msg']?.toString() ?? 
                 'Login failed';
      } else if (e.response?.data is String) {
        message = e.response!.data as String;
      } else if (e.message != null) {
        message = e.message!;
      }
      
      throw Exception(message);
    } catch (e) {
      print('❌ Login failed with general error: $e');
      throw Exception('Network error: ${e.toString()}');
    }
  }
}

