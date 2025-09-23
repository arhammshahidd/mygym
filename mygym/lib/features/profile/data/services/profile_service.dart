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
      final Response response = await client.dio.get(AppConfig.profilePath);
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {'data': response.data};
        return User.fromJson(data);
      } else {
        throw Exception('Failed to fetch profile: ${response.statusMessage}');
      }
    } on DioException catch (e) {
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
      throw Exception('Network error: ${e.toString()}');
    }
  }

  Future<User> updateUserProfile(User user) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token');
    
    final client = ApiClient(authToken: token);
    
    try {
      final Response response = await client.dio.put(
        AppConfig.profilePath,
        data: user.toJson(),
      );
      if (response.statusCode == 200) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {'data': response.data};
        return User.fromJson(data);
      } else {
        throw Exception('Failed to update profile: ${response.statusMessage}');
      }
    } on DioException catch (e) {
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
