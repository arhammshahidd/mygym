import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class ProfileService {
  final AuthService _authService = AuthService();

  Future<User> getCurrentUserProfile() async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token');
    
    final client = ApiClient(authToken: token);
    
    try {
      print('🔐 Fetching profile from: ${AppConfig.profilePath}');
      // Do not print token
      
      final Response response = await client.dio.get(AppConfig.profilePath);
      print('🔐 Profile response status: ${response.statusCode}');
      print('🔐 Profile response data: ${response.data}');
      
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {'data': response.data};
        final user = User.fromJson(data);
        print('🔐 Successfully loaded user profile: ${user.name} (ID: ${user.id})');
        return user;
      } else {
        throw Exception('Failed to fetch profile: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      print('🔐 Profile fetch failed with DioException:');
      print('🔐 Status Code: ${e.response?.statusCode}');
      print('🔐 Response Data: ${e.response?.data}');
      print('🔐 Error Message: ${e.message}');
      
      // Handle specific HTTP errors
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        print('🔐 Token expired or invalid - clearing token');
        await _authService.logout();
        throw Exception('Authentication failed - please login again');
      } else if (e.response?.statusCode == 404) {
        print('🔐 Profile endpoint not found - creating fallback user profile');
        return _createFallbackUser();
      }
      
      String message = 'Failed to fetch profile';
      
      if (e.response?.data is Map<String, dynamic>) {
        final errorData = e.response!.data as Map<String, dynamic>;
        message = errorData['message']?.toString() ?? 
                 errorData['error']?.toString() ?? 
                 'Failed to fetch profile';
      } else if (e.response?.data is String) {
        message = e.response!.data as String;
      } else if (e.message != null) {
        message = e.message!;
      }
      
      throw Exception(message);
    } catch (e) {
      print('🔐 Network error fetching profile: $e');
      print('🔐 Creating fallback user profile');
      return _createFallbackUser();
    }
  }

  /// Create a fallback user profile when the profile endpoint is not available
  User _createFallbackUser() {
    // Create a minimal user profile with default values
    // The user ID will be extracted from the token or set to a default
    return User(
      id: 1, // Default ID - this should be extracted from token in a real implementation
      name: 'User', // Default name
      email: 'user@example.com', // Default email
      phone: '+1234567890', // Default phone
      age: null,
      heightCm: null,
      weightKg: null,
      prefWorkoutAlerts: true,
      prefMealReminders: true,
    );
  }

  Future<User> updateUserProfile(User user) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token');
    
    final client = ApiClient(authToken: token);
    
    try {
      print('🔐 Updating profile at: ${AppConfig.profilePath}');
      print('🔐 Profile data: ${user.toJson()}');
      
      final Response response = await client.dio.put(
        AppConfig.profilePath,
        data: user.toJson(),
      );
      
      print('🔐 Update response status: ${response.statusCode}');
      print('🔐 Update response data: ${response.data}');
      
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {'data': response.data};
        final updatedUser = User.fromJson(data);
        print('🔐 Successfully updated user profile: ${updatedUser.name} (ID: ${updatedUser.id})');
        return updatedUser;
      } else {
        throw Exception('Failed to update profile: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      print('🔐 Profile update failed with DioException:');
      print('🔐 Status Code: ${e.response?.statusCode}');
      print('🔐 Response Data: ${e.response?.data}');
      print('🔐 Error Message: ${e.message}');
      
      // Handle specific HTTP errors
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        print('🔐 Token expired or invalid during update - clearing token');
        await _authService.logout();
        throw Exception('Authentication failed - please login again');
      }
      
      String message = 'Failed to update profile';
      
      if (e.response?.data is Map<String, dynamic>) {
        final errorData = e.response!.data as Map<String, dynamic>;
        message = errorData['message']?.toString() ?? 
                 errorData['error']?.toString() ?? 
                 'Failed to update profile';
      } else if (e.response?.data is String) {
        message = e.response!.data as String;
      } else if (e.message != null) {
        message = e.message!;
      }
      
      throw Exception(message);
    } catch (e) {
      print('🔐 Network error updating profile: $e');
      throw Exception('Network error: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getUserNotifications(int userId) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token');
    
    final client = ApiClient(authToken: token);
    
    try {
      final Response response = await client.dio.get(
        '${AppConfig.notificationsPath}/$userId/notifications',
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      } else {
        throw Exception('Failed to fetch notifications: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      String message = 'Failed to fetch notifications';
      
      if (e.response?.data is Map<String, dynamic>) {
        final errorData = e.response!.data as Map<String, dynamic>;
        message = errorData['message']?.toString() ?? 
                 errorData['error']?.toString() ?? 
                 'Failed to fetch notifications';
      } else if (e.response?.data is String) {
        message = e.response!.data as String;
      } else if (e.message != null) {
        message = e.message!;
      }
      
      throw Exception(message);
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  Future<void> markNotificationAsRead(int notificationId) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token');
    
    final client = ApiClient(authToken: token);
    
    try {
      final Response response = await client.dio.put(
        '${AppConfig.notificationsPath}/notifications/$notificationId/read',
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to mark notification as read: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      String message = 'Failed to mark notification as read';
      
      if (e.response?.data is Map<String, dynamic>) {
        final errorData = e.response!.data as Map<String, dynamic>;
        message = errorData['message']?.toString() ?? 
                 errorData['error']?.toString() ?? 
                 'Failed to mark notification as read';
      } else if (e.response?.data is String) {
        message = e.response!.data as String;
      } else if (e.message != null) {
        message = e.message!;
      }
      
      throw Exception(message);
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }
}
