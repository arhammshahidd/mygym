import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../../shared/widgets/main_tab_screen.dart';
import '../pages/login_page.dart';

class AuthController extends GetxController {
  final AuthService _authService = AuthService();
  
  // Observable variables
  final _isLoggedIn = false.obs;
  final _isLoading = false.obs;
  final _errorMessage = ''.obs;

  // Getters
  bool get isLoggedIn => _isLoggedIn.value;
  bool get isLoading => _isLoading.value;
  String get errorMessage => _errorMessage.value;

  @override
  void onInit() {
    super.onInit();
    _checkAuthStatus();
    
    // Periodically validate token in background (every 5 minutes)
    // This ensures we catch session expiration without being too aggressive
    _startTokenValidationTimer();
  }

  void _startTokenValidationTimer() {
    // Validate token every 5 minutes if user is logged in
    Future.delayed(const Duration(minutes: 5), () {
      if (_isLoggedIn.value) {
        _validateTokenInBackground();
        _startTokenValidationTimer(); // Schedule next validation
      }
    });
  }

  Future<void> _validateTokenInBackground() async {
    try {
      print('🔐 Background token validation...');
      final isValid = await _authService.validateTokenWithBackend();
      if (!isValid) {
        print('🔐 Token invalid in background - but not logging out to avoid disruption');
        // Don't automatically logout on background validation failures
        // This prevents users from being logged out due to network issues
      } else {
        print('🔐 Token valid in background');
      }
    } catch (e) {
      print('🔐 Background token validation failed: $e - not logging out');
      // Don't logout on background validation errors
    }
  }

  Future<void> _checkAuthStatus() async {
    try {
      _isLoading.value = true;
      print('🔐 Checking authentication status...');
      
      final loggedIn = await _authService.isLoggedIn();
      _isLoggedIn.value = loggedIn;
      
      if (loggedIn) {
        print('🔐 User is authenticated');
      } else {
        print('🔐 User is not authenticated');
      }
    } catch (e) {
      print('🔐 Auth status check failed: $e');
      _errorMessage.value = e.toString();
      _isLoggedIn.value = false;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> login(String phone, String password) async {
    try {
      _isLoading.value = true;
      _errorMessage.value = '';
      
      await _authService.login(phone: phone, password: password);
      _isLoggedIn.value = true;
      
      // Load user profile after successful login
      try {
        final profileController = Get.find<ProfileController>();
        await profileController.loadUserProfile();
      } catch (e) {
        print('Warning: Failed to load user profile after login: $e');
      }
      
      // Navigate to main tab screen (no named routes needed)
      if (Get.currentRoute != '/') {
        Get.offAll(() => const MainTabScreen());
      } else {
        // On web hot restart, avoid route churn
        Get.offAll(() => const MainTabScreen());
      }
      
      Get.snackbar(
        'Success',
        'Logged in successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Colors.white,
      );
    } catch (e) {
      _errorMessage.value = e.toString();
      Get.snackbar(
        'Login Failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> logout() async {
    try {
      _isLoading.value = true;
      await _authService.logout();
      _isLoggedIn.value = false;
      
      // Clear user profile data
      try {
        final profileController = Get.find<ProfileController>();
        profileController.clearUser();
      } catch (e) {
        print('Warning: Failed to clear profile data: $e');
      }
      
      // Navigate to login page (avoid duplicate navigations on web reloads)
      Get.offAll(() => const LoginPage());
      Get.snackbar(
        'Logged Out',
        'You have been logged out successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Colors.white,
      );
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  void clearError() {
    _errorMessage.value = '';
  }
}
