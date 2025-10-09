import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';

class AuthService {
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.authToken);
    
    // If no token exists, user is not logged in
    if (token == null || token.isEmpty) {
      print('🔐 No token found in storage');
      return false;
    }
    
    // If token exists, assume user is logged in for app reload scenarios
    // Only validate with backend if explicitly requested or on first login
    print('🔐 Token found in storage - user is logged in');
    return true;
  }

  /// Validate token with backend - only call this when needed
  Future<bool> validateTokenWithBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.authToken);
    
    if (token == null || token.isEmpty) {
      return false;
    }
    
    // Validate token with backend to ensure it's still valid
    try {
      final client = ApiClient(authToken: token);
      final response = await client.dio.get('/api/auth/validate');
      
      // If validation succeeds, user is logged in
      if (response.statusCode == 200) {
        print('🔐 Token validation successful');
        return true;
      }
    } on DioException catch (e) {
      // Handle specific HTTP errors
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        print('🔐 Token expired or invalid (${e.response?.statusCode})');
        // Clear invalid token
        await logout();
        return false;
      } else if (e.response?.statusCode == 404) {
        // If validation endpoint doesn't exist, fall back to profile check
        print('🔐 Validation endpoint not found, checking profile instead');
        return await _validateTokenViaProfile(token);
      } else {
        // Network error or other issues - assume token is still valid
        print('🔐 Token validation failed due to network error: ${e.message} - assuming token is still valid');
        return true; // Don't logout on network errors
      }
    } catch (e) {
      // Other errors - assume token is still valid
      print('🔐 Token validation failed with general error: $e - assuming token is still valid');
      return true; // Don't logout on general errors
    }
    
    return false;
  }

  /// Fallback validation method using profile endpoint
  Future<bool> _validateTokenViaProfile(String token) async {
    try {
      final client = ApiClient(authToken: token);
      final response = await client.dio.get('/api/profile');
      
      if (response.statusCode == 200) {
        print('🔐 Token validation via profile successful');
        return true;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        print('🔐 Token expired or invalid via profile check (${e.response?.statusCode})');
        await logout();
        return false;
      } else if (e.response?.statusCode == 404) {
        // Profile endpoint doesn't exist either - assume token is valid
        print('🔐 Profile endpoint not found - assuming token is valid');
        return true;
      }
    } catch (e) {
      print('🔐 Profile validation failed: $e - assuming token is valid');
      return true; // Don't logout on profile validation errors
    }
    
    return false;
  }

  Future<bool> validateToken() async {
    // Use the new backend validation method
    return await validateTokenWithBackend();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.authToken);
    print('🔐 User logged out - token cleared');
  }

  /// Handle session expiration - called when 401 is received
  Future<void> handleSessionExpiration() async {
    print('🔐 Session expired - clearing token and logging out');
    await logout();
  }

  /// Check if user is inactive from web portal
  Future<bool> isUserInactive() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return true;
    }
    
    try {
      final client = ApiClient(authToken: token);
      final response = await client.dio.get('/api/auth/status');
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final isActive = data['is_active'] ?? data['active'] ?? true;
        return !isActive;
      }
    } catch (e) {
      print('🔐 Error checking user status: $e');
    }
    
    return false;
  }

  /// Validate token when user makes API calls - called by global interceptor
  Future<bool> validateTokenOnApiCall() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.authToken);
    
    if (token == null || token.isEmpty) {
      return false;
    }
    
    // Only validate with backend if we get a 401 error
    // This prevents unnecessary network calls on every API request
    return true; // Assume valid until proven otherwise by 401 response
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

